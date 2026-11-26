import { runMiniAppOperation } from "file:\/\/\/Users\/m1\/Library\/Developer\/CoreSimulator\/Devices\/E742FBCD-8FF0-4130-B143-7F8328637138\/data\/Containers\/Data\/Application\/F0EE35A7-752E-4DE3-9525-844169EBFCCE\/Library\/Application%20Support\/HanlinRuntime\/v1\/runtime\/node\/host-7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc\/miniapp-authoring.mjs";
const report = await runMiniAppOperation({"operation":"sdk","engine":"nativescript"}, {sdkRoot: "\/Users\/m1\/Library\/Developer\/CoreSimulator\/Devices\/E742FBCD-8FF0-4130-B143-7F8328637138\/data\/Containers\/Data\/Application\/F0EE35A7-752E-4DE3-9525-844169EBFCCE\/Library\/Application Support\/HanlinRuntime\/v1\/runtime\/node\/host-7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc\/MiniAppSDK"});
const receipt = { ...report, executionID: "88b040c6-c999-462d-a105-fe855e844212" };
console.log(JSON.stringify(receipt));
process.exitCode = receipt.succeeded === false ? 1 : 0;
export default receipt;