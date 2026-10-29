import fs from 'node:fs/promises';
import path from 'node:path';
import { execSync } from 'node:child_process';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const outputDir = path.join(repoRoot, 'Fixtures/Widgets');
const uiTestFixtures = path.join(repoRoot, 'AI_HLYUITests/Fixtures');

await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(uiTestFixtures, { recursive: true });

async function createArchive(pkgName, ext, files) {
  const stagingDir = path.join(outputDir, `.staging-${pkgName}`);
  await fs.rm(stagingDir, { recursive: true, force: true });
  await fs.mkdir(stagingDir, { recursive: true });

  for (const [relPath, content] of Object.entries(files)) {
    const fullPath = path.join(stagingDir, relPath);
    await fs.mkdir(path.dirname(fullPath), { recursive: true });
    await fs.writeFile(fullPath, content, 'utf8');
  }

  const archiveName = `${pkgName}.${ext}`;
  const outPath1 = path.join(outputDir, archiveName);
  const outPath2 = path.join(uiTestFixtures, archiveName);

  await fs.rm(outPath1, { force: true });
  await fs.rm(outPath2, { force: true });

  const pythonBin = process.platform === 'win32' ? 'python' : 'python3';
  const pyCmd = `${pythonBin} -c "import zipfile, os, sys; zf = zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED); [zf.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), sys.argv[2]).replace('\\\\\\\\', '/')) for r, d, files in os.walk(sys.argv[2]) for f in files]; zf.close()" "${outPath1}" "${stagingDir}"`;
  execSync(pyCmd);

  await fs.copyFile(outPath1, outPath2);
  console.log(`[HanlinWidgets] Created package ${archiveName} (${(await fs.stat(outPath1)).size} bytes)`);
  await fs.rm(stagingDir, { recursive: true, force: true });
}

// 1. Hanlin-Expo-Widget-Counter
await createArchive('Hanlin-Expo-Widget-Counter', 'hanlinExpo', {
  'package.json': JSON.stringify({
    name: 'hanlin-expo-widget-counter',
    version: '1.0.0',
    description: 'Interactive counter widget with native AppIntent button execution'
  }, null, 2),
  'script.json': JSON.stringify({
    name: 'Expo Counter Widget',
    version: '1.0.0',
    entry: 'widget.js',
    hanlinRuntime: 'hanlin-expo',
    kind: 'widget',
    capabilities: ['storage']
  }, null, 2),
  'widget.js': `
    function layout(props, env) {
      const count = props.count || 0;
      return {
        type: 'VStackView',
        props: {
          spacing: 8,
          padding: 12,
          background: '#1A1A1A',
          cornerRadius: 16,
          children: [
            {
              type: 'TextView',
              props: { text: 'Expo Counter', font: 'headline', color: '#888888' }
            },
            {
              type: 'TextView',
              props: { text: String(count), font: 'title', fontSize: 36, color: '#FFFFFF', fontWeight: 'bold' }
            },
            {
              type: 'Button',
              props: {
                title: 'Increment +1',
                target: 'increment_target',
                onButtonPress: () => ({ action: 'increment', newCount: count + 1 })
              }
            }
          ]
        }
      };
    }
  `
});

// 2. Hanlin-Expo-Widget-Visuals
await createArchive('Hanlin-Expo-Widget-Visuals', 'hanlinExpo', {
  'package.json': JSON.stringify({
    name: 'hanlin-expo-widget-visuals',
    version: '1.0.0',
    description: 'Rich native visual widget with Charts, Gauges, Shapes and Progress'
  }, null, 2),
  'script.json': JSON.stringify({
    name: 'Expo Visuals Widget',
    version: '1.0.0',
    entry: 'widget.js',
    hanlinRuntime: 'hanlin-expo',
    kind: 'widget'
  }, null, 2),
  'widget.js': `
    function layout(props, env) {
      return {
        type: 'VStackView',
        props: {
          spacing: 10,
          padding: 12,
          children: [
            {
              type: 'HStackView',
              props: {
                spacing: 6,
                children: [
                  { type: 'ImageView', props: { systemName: 'chart.bar.fill', color: '#007AFF' } },
                  { type: 'TextView', props: { text: 'Performance Metrics', font: 'headline' } }
                ]
              }
            },
            {
              type: 'ChartView',
              props: {
                chartType: 'bar',
                data: [
                  { x: 'Mon', y: 15 },
                  { x: 'Tue', y: 35 },
                  { x: 'Wed', y: 55 },
                  { x: 'Thu', y: 80 }
                ]
              }
            },
            {
              type: 'GaugeView',
              props: { value: 72, min: 0, max: 100, label: 'CPU Usage' }
            }
          ]
        }
      };
    }
  `
});

// 3. Hanlin-ScriptWidget-Dashboard
await createArchive('Hanlin-ScriptWidget-Dashboard', 'scripting', {
  'script.json': JSON.stringify({
    name: 'ScriptWidget Dashboard',
    version: '1.0.0',
    entry: 'widget.jsx',
    hanlinRuntime: 'scripting-jsc',
    kind: 'widget'
  }, null, 2),
  'widget.jsx': `
    function main() {
      return (
        <vstack spacing={8} padding={10}>
          <hstack spacing={6}>
            <badge color="#FF9500">ACTIVE</badge>
            <spacer />
            <date style="time" font="caption" color="#888888" />
          </hstack>
          <stat title="Daily Queries" value="4,821" trend="+14.2%" />
          <ring value={0.82} color="#34C759" lineWidth={6} width={40} height={40} />
          <chart type="bar" data={[{x:"A",y:30},{x:"B",y:60},{x:"C",y:90}]} />
        </vstack>
      );
    }
  `
});

// 4. Hanlin-ScriptWidget-Actions
await createArchive('Hanlin-ScriptWidget-Actions', 'scripting', {
  'script.json': JSON.stringify({
    name: 'ScriptWidget Actions',
    version: '1.0.0',
    entry: 'widget.jsx',
    hanlinRuntime: 'scripting-jsc',
    kind: 'widget'
  }, null, 2),
  'widget.jsx': `
    function main() {
      return (
        <vstack spacing={10} padding={12}>
          <text font="headline" bold={true}>Widget Actions</text>
          <toggle label="Auto Backup" isOn={true} />
          <button title="Trigger Sync" action="sync_now" />
          <link title="Documentation" url="https://github.com/davidpovarsky/hanlin-ai" />
        </vstack>
      );
    }
  `
});

// 5. Hanlin-Mixed-Native-Widget
await createArchive('Hanlin-Mixed-Native-Widget', 'hanlinExpo', {
  'package.json': JSON.stringify({
    name: 'hanlin-mixed-native-widget',
    version: '1.0.0',
    description: 'Advanced mixed-tree widget embedding ScriptWidget JSX inside Expo layout'
  }, null, 2),
  'script.json': JSON.stringify({
    name: 'Mixed Native Widget',
    version: '1.0.0',
    entry: 'widget.js',
    hanlinRuntime: 'hanlin-expo',
    kind: 'widget'
  }, null, 2),
  'widget.js': `
    function layout(props, env) {
      return {
        type: 'VStackView',
        props: {
          spacing: 8,
          padding: 12,
          children: [
            {
              type: 'TextView',
              props: { text: 'Expo Layout Container', font: 'headline', color: '#007AFF' }
            },
            {
              type: 'ScriptWidgetSubtree',
              props: {
                script: \`
                  function main() {
                    return (
                      <vstack spacing={4}>
                        <badge color="#AF52DE">EMBEDDED JSX</badge>
                        <text font="caption" italic={true}>Rendered via ScriptWidget inside Expo!</text>
                      </vstack>
                    );
                  }
                \`
              }
            }
          ]
        }
      };
    }
  `
});

// 6. Hanlin-Widget-Legacy-Regression
await createArchive('Hanlin-Widget-Legacy-Regression', 'scripting', {
  'script.json': JSON.stringify({
    name: 'Widget Legacy Regression',
    version: '1.0.0',
    entry: 'widget.json',
    hanlinRuntime: 'scripting-jsc',
    kind: 'widget'
  }, null, 2),
  'widget.json': JSON.stringify({
    kind: 'vStack',
    properties: { spacing: 6, padding: 8 },
    children: [
      {
        kind: 'text',
        properties: { text: 'Legacy HanlinScriptUINode Tree', font: 16, fontWeight: 'bold' }
      },
      {
        kind: 'text',
        properties: { text: 'Verifying backwards compatibility fallback', opacity: 0.8 }
      }
    ]
  }, null, 2)
});

// 7. Hanlin-Widget-Invalid-Cases
await createArchive('Hanlin-Widget-Invalid-Cases', 'hanlinExpo', {
  'package.json': JSON.stringify({
    name: 'hanlin-widget-invalid-cases',
    version: '1.0.0',
    description: 'Malformed inputs for defensive verification'
  }, null, 2),
  'script.json': JSON.stringify({
    name: 'Invalid Cases Probe',
    version: '1.0.0',
    entry: 'widget.js',
    hanlinRuntime: 'hanlin-expo',
    kind: 'widget'
  }, null, 2),
  'widget.js': `
    // Intentionally corrupted syntax to test fallback handling
    function layout(props, env) {
      throw new Error("Deliberate failure in probe layout");
    }
  `
});

console.log('[HanlinWidgets] All 7 sample packages generated successfully.');
