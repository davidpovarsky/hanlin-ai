"""Run-instance ownership and bounded readiness for an installed image device."""
import hashlib
import json
import re
from guards import environment, owned_uuid, device_rows, require, RUNTIME_ID

CONTRACT = 'composer-precreated-27.2-v3-20261115'
READINESS_SECONDS = 600


def runner_instance(context, boot_uuid, os_build, hostname):
    require(context.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'exclusive ephemeral GitHub-hosted VM required')
    require(context.get('RUNNER_OS') == 'macOS' and context.get('RUNNER_ARCH') == 'ARM64', 'actual arm64 Mac runner required')
    require(re.fullmatch(r'[1-9][0-9]*', context.get('GITHUB_RUN_ID', '')) is not None and
            context.get('GITHUB_RUN_ATTEMPT') == '1', 'one actual manual run attempt required')
    require(all(context.get(key) for key in ['GITHUB_JOB', 'RUNNER_NAME']), 'actual job and runner name required')
    owned_uuid(boot_uuid)
    require(bool(hostname) and re.fullmatch(r'[A-Za-z0-9.]+', os_build) is not None, 'actual VM hostname/OS image build required')
    value = dict(context, kernel_boot_session_uuid=boot_uuid, macOS_build=os_build, hostname=hostname,
                 image_metadata_available=bool(context.get('ImageVersion')), ownership_contract=CONTRACT)
    value['instance_fingerprint'] = hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
    return value


def claim_precreated(before, instance):
    runtime, model = environment(before)
    require(bool(model.get('modelIdentifier')), 'actual inventory hardware model identifier required')
    value = dict(instance)
    fingerprint = value.pop('instance_fingerprint', None)
    require(fingerprint == hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest(), 'runner-instance receipt drift')
    require(instance.get('ownership_contract') == CONTRACT and instance.get('instance_fingerprint'), 'runner-instance receipt required')
    candidates = [row for row in before.get('devices', {}).get(RUNTIME_ID, [])
                  if row.get('isAvailable') is True and row.get('deviceTypeIdentifier') == model['identifier']
                  and row.get('name') == model['name'] and row.get('state') in ['Booted', 'Shutdown']]
    require(bool(candidates), 'no compatible installed precreated standard-runtime phone; no cold-device fallback')
    candidates.sort(key=lambda row: (row['state'] != 'Booted', row['udid']))
    selected = candidates[0]
    owned_uuid(selected.get('udid'))
    require(sum(row.get('udid') == selected['udid'] for _, row in device_rows(before['devices'])) == 1,
            'selected UUID must occur exactly once in actual VM inventory')
    return {'status': 'PRECREATED_DEVICE_CLAIMED_NOT_YET_READY', 'contract': CONTRACT,
            'udid': selected['udid'], 'name': selected['name'], 'initial_device': selected,
            'initial_state': selected['state'], 'runtime': runtime, 'device_type': model,
            'candidate_uuids_in_deterministic_order': [row['udid'] for row in candidates],
            'runner_instance': instance, 'inventory_origin': 'simulators-before.stdout',
            'inventory_fingerprint': hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest(),
            'UUID_globally_unique_between_VMs': False, 'owned_only_in_this_run_instance': True,
            'created_erased_reset_or_renamed': False}


def readiness_help(boot_help, io_help):
    require('Usage:' in boot_help and 'bootstatus' in boot_help and '-b' in boot_help,
            'installed bootstatus usage must document exact-device blocking option')
    require('Usage:' in io_help and 'simctl io' in io_help and 'screenshot' in io_help,
            'installed io usage must document screenshot operation')
    return {'contract': CONTRACT, 'commands': ['simctl bootstatus <owned-UDID> -b',
            'simctl io <owned-UDID> screenshot <owned-path>'], 'readiness_budget_seconds': READINESS_SECONDS,
            'name_enumeration_required': False, 'health_inferred_from_available_or_bootstatus': False}
