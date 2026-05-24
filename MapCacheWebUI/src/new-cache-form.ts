import { useAtom, useAtomValue, useSetAtom } from "jotai";
import {
  cacheLayersAtom,
  cacheZoomDifferentialAtom,
  cacheZoomRangeAtom,
  createCache,
  newCacheDataAtom,
  setRegionName,
  showCacheFormAtom,
} from "./state.ts";
import {
  Button,
  ButtonGroup,
  Card,
  FormGroup,
  InputGroup,
  Slider,
  Switch,
} from "@blueprintjs/core";
import hyper from "@macrostrat/hyper";
import styles from "./cache-list/map-caches.module.sass";
import { capitalize } from "./cache-list/utils.ts";
import { clickHandler } from "./cache-list";

const m = hyper.styled(styles);

export function NewCacheForm() {
  const [cacheData] = useAtom(newCacheDataAtom);
  const [cacheLayers, setCacheLayers] = useAtom(cacheLayersAtom);
  const [zoomDifferential, setZoomDifferential] = useAtom(
    cacheZoomDifferentialAtom,
  );
  const [minZoom, maxZoom] = useAtomValue(cacheZoomRangeAtom);
  const setShowForm = useSetAtom(showCacheFormAtom);

  return m("div.new-cache-form", [
    m("h3", "New cache region"),
    m(InputGroup, {
      value: cacheData.name,
      onValueChange(value) {
        setRegionName(value);
      },
    }),
    m(LabeledControl, { label: "Layers" }, [
      m("div.cache-layers-checkboxes", [
        ["bedrock", "basemap", "satellite"].map((layer) =>
          m(Switch, {
            type: "checkbox",
            label: capitalize(layer),
            checked: cacheLayers[layer],
            onChange: (e) => {
              setCacheLayers((val) => {
                return {
                  ...val,
                  [layer]: e.target.checked,
                };
              });
            },
          }),
        ),
      ]),
    ]),
    m(LabeledControl, { label: "Zoom depth" }, [
      m(Slider, {
        min: 3,
        max: 6,
        stepSize: 1,
        labelStepSize: 1,
        value: zoomDifferential,
        onChange: setZoomDifferential,
      }),
    ]),
    m(LabeledControl, { label: "Zoom range" }, [
      m("span", `${minZoom} – ${maxZoom}`),
    ]),
    m(ButtonGroup, [
      m(
        Button,
        {
          icon: "map-create",
          intent: "primary",
          onClick: clickHandler(createCache),
        },
        "Create cache",
      ),
      m(
        Button,
        {
          icon: "cross",
          intent: "danger",
          onClick() {
            setShowForm(false);
          },
        },
        "Cancel",
      ),
    ]),
  ]);
}

function LabeledControl({ label, children, inline = true }) {
  return m(FormGroup, { label, inline }, children);
}
