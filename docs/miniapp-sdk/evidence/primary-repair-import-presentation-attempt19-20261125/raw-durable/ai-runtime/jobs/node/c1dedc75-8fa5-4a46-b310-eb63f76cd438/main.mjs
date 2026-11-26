import { runMiniAppOperation } from "file:\/\/\/Users\/m1\/Library\/Developer\/CoreSimulator\/Devices\/E742FBCD-8FF0-4130-B143-7F8328637138\/data\/Containers\/Data\/Application\/1CB4DAE0-2652-4BEA-9F29-08A40E7362AF\/Library\/Application%20Support\/HanlinRuntime\/v1\/runtime\/node\/host-7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc\/miniapp-authoring.mjs";
const report = await runMiniAppOperation({"operation":"sdk","engine":"nativescript"}, {sdkRoot: "\/Users\/m1\/Library\/Developer\/CoreSimulator\/Devices\/E742FBCD-8FF0-4130-B143-7F8328637138\/data\/Containers\/Data\/Application\/1CB4DAE0-2652-4BEA-9F29-08A40E7362AF\/Library\/Application Support\/HanlinRuntime\/v1\/runtime\/node\/host-7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc\/MiniAppSDK"});
const receipt = { ...report, executionID: "c1dedc75-8fa5-4a46-b310-eb63f76cd438" };
console.log(JSON.stringify(receipt));
process.exitCode = receipt.succeeded === false ? 1 : 0;
export default receipt;