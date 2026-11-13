import {createHostServices} from '../../host-services';
const host = createHostServices();
host.executeRuntime('python', 'print(42)');
host.executeRuntime('node', '42', {unknownDeadline: 10});
host.executeRuntime('localPython', 'print(42)', {arguments: [42]});
export const onResult = receipt => receipt.stdout;
