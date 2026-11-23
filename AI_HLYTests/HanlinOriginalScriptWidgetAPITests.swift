import Foundation
import Testing
import HanlinPlatformContracts
import HanlinScriptContracts
@testable import HanlinScriptExtensions

struct HanlinOriginalScriptWidgetAPITests {
    private func program(_ source: String, resources: [String: Data] = [:]) -> HanlinWidgetProgram {
        HanlinWidgetProgram(engine: .scriptwidget,
            sourceSHA256: String(repeating: "a", count: 64),
            compilerSHA256: String(repeating: "b", count: 64),
            javaScript: source, actions: [], families: ["systemMedium"], resources: resources)
    }

    @Test
    func originalNativeProvidersAreRegisteredAndExposeRealDeviceValues() throws {
        let source = """
        async function $main() {
          const names = ['$alarms','$calendar','$console','$contacts','$device',
            '$documents','$fetch','$file','$health','$home','$http','$icloud',
            '$location','$maps','$music','$notifications','$photos','$reminders',
            '$runtime','$services','$storage','$system','$weather','fetch','console'];
          const missing = names.filter(name => typeof globalThis[name] === 'undefined');
          if (missing.length) throw new Error('Missing upstream providers: '+missing.join(','));
          $storage.setJSON('native', {
            runtime: $runtime.apiVersion, locale: $system.locale(),
            language: $device.language(), platform: $system.platform()
          });
          $render(ScriptWidget.createElement('text',{},['Original native providers']));
        }
        """
        let result = try HanlinScriptWidgetRuntime.shared.run(program: program(source), values: [:], environment: [:])
        guard case let .object(native)? = result.values["native"] else {
            Issue.record("The original native provider result did not reach the state transaction.")
            return
        }
        #expect(native["locale"] == .string(Locale.current.identifier))
        #expect(native["language"] == .string(Locale.current.language.languageCode?.identifier ?? ""))
        #expect(native["runtime"] != nil)
        #expect(native["platform"] != nil)
    }

    @Test
    func originalAsyncDocumentsProviderSettlesBeforeRenderingAndStateCommit() throws {
        // This exercises the real upstream provider, managed package snapshot,
        // system-service worker, Promise callback queue and original file API.
        // It does not request OS personal-data access or substitute a provider.
        let source = """
        async function $main() {
          const documents = await $documents.list();
          const config = $file.readJSON('config.json');
          $storage.setJSON('native', {count: documents.length, label: config.label});
          $render(ScriptWidget.createElement('text',{},[config.label]));
        }
        """
        let result = try HanlinScriptWidgetRuntime.shared.run(program: program(source,
            resources: ["config.json": Data(#"{"label":"בדיקת ספרייה מקורית"}"#.utf8)]),
            values: [:], environment: [:])
        guard case let .object(native)? = result.values["native"] else {
            Issue.record("The upstream native Promise did not settle.")
            return
        }
        #expect(native["count"] == .integer(0))
        #expect(native["label"] == .string("בדיקת ספרייה מקורית"))
    }

    @Test
    func upstreamPromiseRejectionIsCatchableWithoutUnsupportedAsyncFailure() throws {
        let source = """
        async function $main() {
          let failure = '';
          try { await $documents.readJSON('missing-document'); }
          catch (error) { failure = String(error); }
          if (!failure) throw new Error('Missing native document unexpectedly succeeded');
          $storage.setString('nativeFailure', failure);
          $render(ScriptWidget.createElement('text',{},['Native failure handled']));
        }
        """
        let result = try HanlinScriptWidgetRuntime.shared.run(program: program(source), values: [:], environment: [:])
        guard case let .string(message)? = result.values["nativeFailure"] else {
            Issue.record("The actual native failure was not delivered to JavaScript.")
            return
        }
        #expect(!message.isEmpty)
        #expect(!message.contains("unsupported asynchronous operation"))
    }

    @Test
    func originalStorageAndHanlinCompatibilityValuesShareOneTransaction() throws {
        let source = """
        async function $main() {
          if ($storage.getString('title') !== 'before') throw new Error('Missing original string');
          if ($storage.getJSON('object').value !== 1) throw new Error('Missing original JSON');
          if (!$storage.compareAndSetJSON('object', {value:1}, {value:2})) throw new Error('CAS failed');
          $storage.set('flag', true);
          $storage.setString('title', 'after');
          await $documents.list();
          $render(ScriptWidget.createElement('text',{},[$storage.getString('title')]));
        }
        """
        let result = try HanlinScriptWidgetRuntime.shared.run(program: program(source),
            values: ["title": .string("before"), "object": .object(["value": .number(1)])],
            environment: [:])
        #expect(result.values["title"] == .string("after"))
        #expect(result.values["object"] == .object(["value": .integer(2)]))
        #expect(result.values["flag"] == .bool(true))
    }
}
