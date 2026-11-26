import type {WidgetToggleProps, WidgetRefreshButtonProps, HanlinWidgetFamily} from "../../../Packages/HanlinExpoUI/src/widget-types";
const toggle: WidgetToggleProps<{enabled:boolean}> = {isOn:false,target:"enabled",label:"Enabled",onIsOnChange:value=>({enabled:value})};
const refresh: WidgetRefreshButtonProps = {label:"Refresh",widgetRefresh:true};
const portrait: HanlinWidgetFamily = "systemExtraLargePortrait";
// @ts-expect-error a native Toggle must carry a Boolean
const bad: WidgetToggleProps<object> = {isOn:"true", target:"x", onIsOnChange:v=>({})};
// @ts-expect-error unknown family must remain rejected
const unsupported: HanlinWidgetFamily = "systemUnknown";
