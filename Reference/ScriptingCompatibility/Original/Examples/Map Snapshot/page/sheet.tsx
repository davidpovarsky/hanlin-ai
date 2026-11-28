import { Button, useObservable, useContext, Text } from "scripting";
import { server } from "../class/server";
import { MapSelectionContext } from "../context/MapSelection";
import { View as DetailView } from "./detail";

export function View() {
  const selection = useContext(MapSelectionContext);
  const isPresented = useObservable<boolean>(false);
  const selectedId = (selection.value as any)?.tag as string | undefined;
  const selectedPin = server.getPinById(selectedId);

  return (
    <Button
      buttonStyle={"glass"}
      hidden={!selection.value}
      action={() => isPresented.setValue(!isPresented.value)}
      sheet={{
        isPresented: isPresented,
        content: (
          <DetailView selection={selection.value!} presentationDetents={["medium", "large"]} />
        ),
      }}>
      <Text padding={3} font={"title3"} frame={{ minWidth: 150 }} lineLimit={1}>
        {selectedPin?.title || selectedId || ""}
      </Text>
    </Button>
  );
}
