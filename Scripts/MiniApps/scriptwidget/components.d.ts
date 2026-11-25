// Generated from original ScriptWidget editor catalog; do not edit.
// Hanlin host additions are declared separately in host-globals.d.ts.
declare namespace JSX {
  interface Element { readonly __scriptWidgetElement: unique symbol; }
  type Child = Element | string | number | boolean | null | undefined | readonly Child[];
  interface ElementChildrenAttribute { children: {}; }
  interface GlobalProperties {
    "background"?: string;
    "backgroundMaterial"?: "none" | "ultraThin" | "thin" | "regular" | "thick" | "ultraThick";
    "color"?: string;
    "font"?: "largeTitle" | "title" | "title2" | "title3" | "headline" | "subheadline" | "body" | "callout" | "footnote" | "caption" | "caption2";
    "fontWeight"?: "ultraLight" | "thin" | "light" | "regular" | "medium" | "semibold" | "bold" | "heavy" | "black";
    "fontDesign"?: "default" | "rounded" | "serif" | "monospaced";
    "frame"?: number | string;
    "padding"?: number | string;
    "corner"?: number | string;
    "opacity"?: number | string;
    "alignment"?: "center" | "leading" | "trailing" | "top" | "bottom" | "topLeading" | "topTrailing" | "bottomLeading" | "bottomTrailing" | "firstTextBaseline" | "lastTextBaseline";
    "clip"?: "circle" | "rect" | "capsule" | "ellipse";
    "rotation"?: number | string;
    "rotation3d"?: string;
    "shadow"?: string;
    "animation"?: string;
    "widgetAccentable"?: boolean;
    "linkurl"?: string;
    children?: Child;
  }
  interface IntrinsicElements {
    "vstack": GlobalProperties & {
    "spacing"?: number | string;
    };
    "hstack": GlobalProperties & {
    "spacing"?: number | string;
    };
    "zstack": GlobalProperties & {

    };
    "vgrid": GlobalProperties & {
    "columns": string;
    "spacing"?: number | string;
    "alignment"?: "leading" | "center" | "trailing";
    };
    "hgrid": GlobalProperties & {
    "columns": string;
    "spacing"?: number | string;
    "alignment"?: "top" | "center" | "bottom" | "firstTextBaseline" | "lastTextBaseline";
    };
    "text": GlobalProperties & {
    "text"?: string;
    };
    "date": GlobalProperties & {
    "date": number | Date;
    "style"?: "time" | "date" | "relative" | "offset" | "timer";
    };
    "image": GlobalProperties & {
    "systemName"?: string;
    "name"?: string;
    "id"?: string;
    "url"?: string;
    "src"?: string;
    "ratio"?: number | string;
    "mode"?: "fit" | "fill";
    "accentedRenderingMode"?: "accented" | "desaturated" | "accentedDesaturated" | "fullColor";
    };
    "gif": GlobalProperties & {
    "file": string;
    };
    "spacer": GlobalProperties & {
    "minLength"?: number | string;
    };
    "rect": GlobalProperties & {
    "trim"?: number | string;
    "stroke"?: string;
    };
    "roundedrect": GlobalProperties & {
    "radius"?: number | string;
    };
    "capsule": GlobalProperties & {
    "trim"?: number | string;
    "stroke"?: string;
    };
    "ellipse": GlobalProperties & {
    "trim"?: number | string;
    "stroke"?: string;
    };
    "circle": GlobalProperties & {
    "trim"?: number | string;
    "stroke"?: string;
    };
    "gauge": GlobalProperties & {
    "type"?: string;
    "value"?: number | string;
    "style"?: "circular" | "linear";
    "text"?: string;
    "current"?: string;
    "min"?: string;
    "max"?: string;
    "angle"?: number | string;
    "thickness"?: number | string;
    "needleColor"?: string;
    "label"?: string;
    "title"?: string;
    "sections"?: string;
    };
    "chart": GlobalProperties & {
    "type"?: "bar" | "bar-x" | "bar-y" | "bar-gantt" | "line" | "point" | "line-point" | "area" | "rect" | "rule-x";
    "data": string;
    "category"?: boolean;
    "hideLegend"?: boolean;
    "hideXAxis"?: boolean;
    "hideYAxis"?: boolean;
    };
    "link": GlobalProperties & {
    "url": string;
    };
    "divider": GlobalProperties & {
    "thickness"?: number | string;
    "axis"?: "horizontal" | "vertical";
    };
    "line": GlobalProperties & {
    "thickness"?: number | string;
    "length"?: number | string;
    "axis"?: "horizontal" | "vertical";
    };
    "icon": GlobalProperties & {
    "systemName": string;
    "size"?: number | string;
    };
    "label": GlobalProperties & {
    "title"?: string;
    "systemName": string;
    };
    "progress": GlobalProperties & {
    "value": number | string;
    "total"?: number | string;
    "label"?: string;
    "style"?: "linear" | "circular";
    "trackColor"?: string;
    "thickness"?: number | string;
    };
    "ring": GlobalProperties & {
    "value": number | string;
    "thickness"?: number | string;
    "trackColor"?: string;
    };
    "badge": GlobalProperties & {
    "text"?: string;
    "radius"?: number | string;
    };
    "chip": GlobalProperties & {
    "text"?: string;
    "radius"?: number | string;
    "borderColor"?: string;
    };
    "stat": GlobalProperties & {
    "title"?: string;
    "value": string;
    "subtitle"?: string;
    "mutedColor"?: string;
    };
    "button": GlobalProperties & {
    "action"?: "reload";
    "onClick"?: string;
    "actionID"?: string;
    };
    "toggle": GlobalProperties & {
    "on": boolean;
    "onClick"?: string;
    "actionID"?: string;
    "stateKey"?: string;
    };
  }
}
