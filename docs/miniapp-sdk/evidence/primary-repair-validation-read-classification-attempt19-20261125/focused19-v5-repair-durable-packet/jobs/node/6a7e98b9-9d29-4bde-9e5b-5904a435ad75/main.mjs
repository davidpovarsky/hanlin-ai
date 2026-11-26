import { runMiniAppOperation } from "file:\/\/\/Users\/m1\/Library\/Developer\/CoreSimulator\/Devices\/E742FBCD-8FF0-4130-B143-7F8328637138\/data\/Containers\/Data\/Application\/E2B02896-9E6E-47FD-A342-0AE8024D3604\/Library\/Application%20Support\/HanlinRuntime\/v1\/runtime\/node\/host-7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc\/miniapp-authoring.mjs";
const report = await runMiniAppOperation({"operation":"sdk","engine":"nativescript"}, {sdkRoot: "\/Users\/m1\/Library\/Developer\/CoreSimulator\/Devices\/E742FBCD-8FF0-4130-B143-7F8328637138\/data\/Containers\/Data\/Application\/E2B02896-9E6E-47FD-A342-0AE8024D3604\/Library\/Application Support\/HanlinRuntime\/v1\/runtime\/node\/host-7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc\/MiniAppSDK"});
const receipt = { ...report, executionID: "6a7e98b9-9d29-4bde-9e5b-5904a435ad75" };
console.log(JSON.stringify(receipt));
process.exitCode = receipt.succeeded === false ? 1 : 0;
export default receipt;