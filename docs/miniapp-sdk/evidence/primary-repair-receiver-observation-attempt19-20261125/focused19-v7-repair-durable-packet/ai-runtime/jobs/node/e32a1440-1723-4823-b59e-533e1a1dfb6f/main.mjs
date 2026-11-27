import { runMiniAppOperation } from "file:\/\/\/Users\/m1\/Library\/Developer\/CoreSimulator\/Devices\/E742FBCD-8FF0-4130-B143-7F8328637138\/data\/Containers\/Data\/Application\/BB02E47D-090F-49C1-A512-34B1D33D87DB\/Library\/Application%20Support\/HanlinRuntime\/v1\/runtime\/node\/host-7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc\/miniapp-authoring.mjs";
const report = await runMiniAppOperation({"operation":"sdk","engine":"nativescript"}, {sdkRoot: "\/Users\/m1\/Library\/Developer\/CoreSimulator\/Devices\/E742FBCD-8FF0-4130-B143-7F8328637138\/data\/Containers\/Data\/Application\/BB02E47D-090F-49C1-A512-34B1D33D87DB\/Library\/Application Support\/HanlinRuntime\/v1\/runtime\/node\/host-7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc\/MiniAppSDK"});
const receipt = { ...report, executionID: "e32a1440-1723-4823-b59e-533e1a1dfb6f" };
console.log(JSON.stringify(receipt));
process.exitCode = receipt.succeeded === false ? 1 : 0;
export default receipt;