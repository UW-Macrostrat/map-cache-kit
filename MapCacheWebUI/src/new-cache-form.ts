import { useAtom, useSetAtom } from "jotai";
import {
  cacheLayersAtom,
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
  const setShowForm = useSetAtom(showCacheFormAtom);

  return m(Card, [
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
