import {createHostServices, type RuntimeExecutionResult} from '../../host-services';

export async function run(): Promise<RuntimeExecutionResult[]> {
  const host = createHostServices();
  return [
    await host.executeRuntime('node', "console.log('Node')"),
    await host.executeRuntime('typeScript', 'const value: number = 42; console.log(value)'),
    await host.executeRuntime('localPython', "print('Python')", {arguments: ['example'], environment: {EXAMPLE: '1'}}),
    await host.executeRuntime('javaScriptCore', '21 * 2'),
    await host.executeRuntime('shell', 'pwd'),
  ];
}
