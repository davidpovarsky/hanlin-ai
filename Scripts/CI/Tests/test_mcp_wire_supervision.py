"""Portable supervisor safety controls. No native compiler, process query or signals."""
import ast
import copy
import hashlib
import pathlib
import signal
import subprocess
import tempfile
import types
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / "IntegrationValidation/run_host_mcp_wire_comparison.py"
NAMES = {"scoped_ps_query", "process_topology", "process_descendants",
         "owned_process_snapshot", "owned_tree", "process_identity",
         "stop_owned_processes"}
START = "Fri Nov 27 16:00:00 2026"

def row(pid, ppid, pgid, start=START, executable=None):
    return {"pid":pid, "ppid":ppid, "pgid":pgid, "state":"S",
            "processStarted":start, "executable":executable or "/owned/process-"+str(pid)}

def text(rows, identities):
    return "\n".join(
        f'{r["pid"]} {r["ppid"]} {r["pgid"]} {r["state"]} {r["processStarted"]}'
        + ((" "+r["executable"]) if identities else "") for r in rows) + ("\n" if rows else "")

class Clock:
    value = 0.0
    def monotonic(self): return self.value
    def sleep(self, value): self.value += value

class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.steps = []
        self.calls = []
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ns = {
            "time":self.clock, "os":types.SimpleNamespace(getpid=lambda:42,getpgrp=lambda:900),
            "subprocess":types.SimpleNamespace(run=self.run_ps,
                TimeoutExpired=subprocess.TimeoutExpired,CalledProcessError=subprocess.CalledProcessError),
            "known_owned":{}, "data":{}, "now":lambda:"observed", "save":lambda:None,
            "EVIDENCE":pathlib.Path(self.temp.name),
            "digest":lambda p:hashlib.sha256(p.read_bytes()).hexdigest(), "signal":signal}
        tree=ast.parse(SOURCE.read_text())
        selected=ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)
                                  and n.name in NAMES],type_ignores=[])
        exec(compile(selected,str(SOURCE),"exec"),self.ns)

    def run_ps(self, argv, **kwargs):
        self.assertTrue(self.steps, "unexpected process query")
        kind, rows, elapsed, exit_code, raw = self.steps.pop(0)
        self.assertEqual("-p" in argv, kind=="I")
        self.assertTrue(kwargs["capture_output"] and kwargs["text"])
        self.assertFalse(kwargs["check"])
        self.calls.append((argv,kwargs["timeout"]))
        limit=kwargs["timeout"]
        if elapsed > limit:
            self.clock.value += limit
            raise subprocess.TimeoutExpired(argv,limit,output=b"retained partial\n",stderr=b"")
        self.clock.value += elapsed
        if kind=="I":
            requested={int(p) for p in argv[2].split(",")}
            self.assertTrue(set(r["pid"] for r in rows).issubset(requested))
        return types.SimpleNamespace(returncode=exit_code,
                    stdout=raw if raw is not None else text(rows,kind=="I"),stderr="")

    def add(self, kind, rows, elapsed=.01, exit_code=0, raw=None):
        self.steps.append((kind,copy.deepcopy(rows),elapsed,exit_code,raw))

    def snapshot(self):
        result=self.ns["owned_process_snapshot"](100)
        self.assertFalse(self.steps)
        return {r["pid"]:r for r in result}

    def test_complete_foreign_group_members_remain_unowned(self):
        rows=[row(100,42,100),row(110,100,100),row(900,1,100)]
        self.add("T",rows);self.add("I",rows[:2]);self.add("T",rows)
        result=self.snapshot()
        self.assertEqual(set(result),{100,110,900})
        self.assertIsNone(result[900]["executable"])
        self.assertEqual(set(self.ns["known_owned"]),{100,110})
        self.assertEqual(self.calls[1][0][2],"100,110")

    def test_recycled_orphan_pid_is_not_queried_or_owned(self):
        self.ns["known_owned"][110]=(START,"/owned/process-110")
        reused=row(110,1,800,start="Fri Nov 27 16:01:00 2026")
        rows=[row(100,42,100),reused]
        self.add("T",rows);self.add("I",rows[:1]);self.add("T",rows)
        result=self.snapshot()
        self.assertEqual(self.calls[1][0][2],"100")
        self.assertIsNone(result[110]["executable"])
        self.assertNotEqual(self.ns["known_owned"][110],self.ns["process_identity"](result[110]))

    def test_recycled_root_pid_fails_closed(self):
        self.ns["known_owned"][100]=(START,"/owned/process-100")
        self.add("T",[row(100,42,100,start="Fri Nov 27 16:01:00 2026")])
        with self.assertRaisesRegex(RuntimeError,"recycled"):self.snapshot()

    def test_root_outside_original_session_fails_closed(self):
        self.add("T",[row(100,42,800)])
        with self.assertRaisesRegex(RuntimeError,"start_new_session"):self.snapshot()

    def test_new_child_is_observed_before_snapshot_can_return(self):
        parent=row(100,42,100);child=row(110,100,110)
        self.add("T",[parent]);self.add("I",[parent]);self.add("T",[parent,child])
        self.add("I",[parent,child]);self.add("T",[parent,child])
        result=self.snapshot()
        self.assertEqual(result[110]["executable"],child["executable"])
        self.assertEqual(self.ns["data"]["latestScopedProcessSnapshot"]["rounds"],2)

    def test_observed_child_reparent_and_separate_group_remain_owned(self):
        parent=row(100,42,100);before=row(110,100,100);after=row(110,1,110)
        self.add("T",[parent,before]);self.add("I",[parent,before]);self.add("T",[parent,after])
        self.add("I",[parent,after]);self.add("T",[parent,after])
        result=self.snapshot()
        self.assertEqual(result[110]["ppid"],1)
        self.assertEqual(result[110]["pgid"],110)
        self.assertEqual(self.ns["known_owned"][110],self.ns["process_identity"](result[110]))

    def test_changed_identity_before_first_verification_is_not_promoted(self):
        parent=row(100,42,100);old=row(110,100,100)
        replacement=row(110,1,800,start="Fri Nov 27 16:01:00 2026")
        self.add("T",[parent,old]);self.add("I",[parent,replacement])
        self.add("T",[parent,replacement])
        result=self.snapshot()
        self.assertNotIn(110,self.ns["known_owned"])
        self.assertIsNone(result[110]["executable"])

    def test_same_start_orphan_with_changed_executable_stays_unverified(self):
        parent=row(100,42,100);orphan=row(110,1,100,executable="/foreign/new-image")
        self.ns["known_owned"][110]=(START,"/owned/process-110")
        self.add("T",[parent,orphan]);self.add("I",[parent,orphan]);self.add("T",[parent,orphan])
        result=self.snapshot()
        self.assertNotEqual(self.ns["known_owned"][110],self.ns["process_identity"](result[110]))

    def test_all_selected_pids_exited_requires_fresh_complete_confirmation(self):
        parent=row(100,42,100)
        self.add("T",[parent]);self.add("I",[],exit_code=1);self.add("T",[])
        self.assertEqual(self.snapshot(),{})
        self.assertEqual(len(self.calls),3)

    def test_missing_but_still_live_pid_is_requeried_within_same_budget(self):
        parent=row(100,42,100)
        self.add("T",[parent]);self.add("I",[],exit_code=1);self.add("T",[parent])
        self.add("I",[parent]);self.add("T",[parent])
        self.assertEqual(set(self.snapshot()),{100})
        self.assertEqual(self.ns["data"]["latestScopedProcessSnapshot"]["rounds"],2)

    def test_original_ten_seconds_is_shared_by_all_queries(self):
        parent=row(100,42,100)
        self.add("T",[parent],elapsed=2)
        self.add("I",[parent],elapsed=3)
        self.add("T",[parent],elapsed=4)
        self.snapshot()
        self.assertEqual([x[1] for x in self.calls],[10,8,5])
        self.assertEqual(self.ns["data"]["latestScopedProcessSnapshot"]["elapsedSeconds"],9)

    def test_shared_deadline_timeout_retains_actual_partial_output(self):
        parent=row(100,42,100)
        self.add("T",[parent],elapsed=2)
        self.add("I",[parent],elapsed=3)
        self.add("T",[parent],elapsed=6)
        with self.assertRaises(subprocess.TimeoutExpired):self.snapshot()
        self.assertEqual(self.clock.value,10)
        record=self.ns["data"]["failedScopedProcessQuery"]["stdout"]
        self.assertEqual(pathlib.Path(record["path"]).read_bytes(),b"retained partial\n")
        self.assertEqual([x[1] for x in self.calls],[10,8,5])

    def test_unparseable_or_duplicate_topology_never_becomes_partial_success(self):
        for raw in ["not a process row\n",text([row(100,42,100)]*2,False)]:
            with self.subTest(raw=raw):
                self.add("T",[],raw=raw)
                with self.assertRaises(RuntimeError):self.snapshot()

    def test_second_cleanup_timeout_preserves_first_raw_failure(self):
        parent=row(100,42,100)
        argv=["/bin/ps","-p","100","-o","pid=,ppid=,pgid=,stat=,lstart=,comm="]
        for _ in range(2):
            self.add("I",[parent],elapsed=11)
            with self.assertRaises(subprocess.TimeoutExpired):
                self.ns["scoped_ps_query"](argv,self.clock.value+10,True)
        failures=self.ns["data"]["failedScopedProcessQueries"]
        self.assertEqual(len(failures),2)
        self.assertNotEqual(failures[0]["stdout"]["path"],failures[1]["stdout"]["path"])
        for failure in failures:
            self.assertEqual(pathlib.Path(failure["stdout"]["path"]).read_bytes(),b"retained partial\n")

    def test_shared_group_is_never_signalled_and_unknown_member_survives(self):
        parent=row(100,42,100);foreign=row(900,1,100);foreign["executable"]=None
        snapshots=[[parent,foreign],[parent,foreign],[foreign],[foreign]]
        self.ns["owned_process_snapshot"]=lambda pid:copy.deepcopy(snapshots.pop(0))
        actions=[]
        process=types.SimpleNamespace(pid=100,poll=lambda:None if not actions else 130)
        self.ns["os"].kill=lambda pid,sig:actions.append(("pid",pid,sig))
        self.ns["os"].killpg=lambda pgid,sig:actions.append(("group",pgid,sig))
        self.ns["stop_owned_processes"](process,"CONTROLLED_NEGATIVE_CASE")
        self.assertEqual(actions,[("pid",100,signal.SIGINT)])
        self.assertEqual(self.ns["data"]["ownedProcessesAfterStop"],[])
        self.assertFalse(snapshots)

    def test_verified_escaped_child_group_is_stopped_with_parent_group(self):
        parent=row(100,42,100);child=row(110,1,110)
        self.ns["known_owned"][110]=self.ns["process_identity"](child)
        snapshots=[[parent,child],[parent,child],[],[]]
        self.ns["owned_process_snapshot"]=lambda pid:copy.deepcopy(snapshots.pop(0))
        actions=[]
        process=types.SimpleNamespace(pid=100,poll=lambda:None if not actions else 130)
        self.ns["os"].kill=lambda pid,sig:actions.append(("pid",pid,sig))
        self.ns["os"].killpg=lambda pgid,sig:actions.append(("group",pgid,sig))
        self.ns["stop_owned_processes"](process,"CONTROLLED_ESCAPE_CASE")
        self.assertEqual(actions,[("group",100,signal.SIGINT),("group",110,signal.SIGINT)])
        self.assertEqual(self.ns["data"]["ownedProcessesAfterStop"],[])
        self.assertFalse(snapshots)

if __name__=="__main__":
    unittest.main(verbosity=2)
