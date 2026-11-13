#!/usr/bin/env node
// Writes the P1-5 style-slice themes godot/art/theme/slice_{a,b,c}.tres from
// default_theme.tres: each is the default with its figure treatment and its
// lighting swapped in. Re-run after editing the default so the slice stays a
// comparison of the treatments only.  node autobuild/slice_themes.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const THEME_DIR = join(resolve(dirname(fileURLToPath(import.meta.url)), ".."), "godot/art/theme");
const base = readFileSync(join(THEME_DIR, "default_theme.tres"), "utf8");

const MALE = "res://art/characters/figure_male.gltf";
const bones = (map) => `Dictionary[StringName, Vector3]({\n${Object.entries(map)
  .map(([k, v]) => `&"${k}": Vector3(${v.join(", ")})`).join(",\n")}\n})`;

const VARIANTS = {
  // A "Putty": STYLE §2.3 as written. One satin warm putty grey, no clothes, the
  // STYLE §2.2 dad nudge (torso a touch long). Lighting: the P1-4 default.
  a: {
    figure: { albedo_color: "Color(0.72, 0.69, 0.64, 1)", roughness: "0.55" },
    bones: { spine_02: [1, 1.06, 1], hand_l: [1.06, 1.06, 1.06], hand_r: [1.06, 1.06, 1.06] },
    light: {},
  },
  // B "Painted": the same bodies in plain painted clothes (vertex colour baked
  // by figure_bake.mjs: blue-grey shirt, taupe trousers, dark shoes), bare putty
  // head and hands, matt. Lighting: warm lamplit interior, low sun.
  b: {
    figure: {
      albedo_color: "Color(0.76, 0.72, 0.66, 1)", roughness: "0.8",
      vertex_color_use_as_albedo: "true", vertex_color_is_srgb: "true",
    },
    bones: { spine_02: [1, 1.06, 1], hand_l: [1.06, 1.06, 1.06], hand_r: [1.06, 1.06, 1.06] },
    light: {
      interior_lamps: "true", interior_energy: "1.4", sun_energy: "0.28",
      ambient_colour: "Color(0.82, 0.72, 0.6, 1)", ambient_energy: "0.55", sky_fill_energy: "0.35",
    },
  },
  // C "Vinyl, odd": smooth pale vinyl (D10's "smooth plastic-like"), a clearly
  // too-big head on a long neck, small hands - the strongest "slightly off".
  // Lighting: bright overcast, no sun shadow, cool even ambient.
  c: {
    figure: { albedo_color: "Color(0.84, 0.81, 0.76, 1)", roughness: "0.3", metallic_specular: "0.6" },
    bones: { Head: [1.14, 1.14, 1.14], neck_01: [1, 1.18, 1], hand_l: [0.9, 0.9, 0.9], hand_r: [0.9, 0.9, 0.9] },
    light: {
      sun_shadows: "false", sun_energy: "0.25", ambient_colour: "Color(0.78, 0.8, 0.84, 1)",
      ambient_energy: "0.95", fill_energy: "0.3", sky_fill_colour: "Color(0.95, 0.95, 0.95, 1)",
    },
  },
};

function setProp(text, section, key, value) {
  // section: the text block to edit (a sub_resource body or the [resource] body).
  const line = new RegExp(`^${key} = .*$`, "m");
  return line.test(section.body)
    ? { ...section, body: section.body.replace(line, `${key} = ${value}`) }
    : { ...section, body: `${section.body.trimEnd()}\n${key} = ${value}\n` };
}

for (const [name, v] of Object.entries(VARIANTS)) {
  let text = base;
  // The figure material block.
  const figStart = text.indexOf('[sub_resource type="StandardMaterial3D" id="figure"]');
  const figEnd = text.indexOf("\n[", figStart + 1);
  let fig = { body: text.slice(figStart, figEnd) };
  for (const [k, val] of Object.entries(v.figure)) fig = setProp(text, fig, k, val);
  text = `${text.slice(0, figStart)}${fig.body.trimEnd()}\n${text.slice(figEnd)}`;
  // The resource block.
  const resStart = text.indexOf("[resource]");
  let res = { body: text.slice(resStart) };
  const props = {
    figure_model: `"${MALE}"`, figure_height: "180.0", figure_bone_scales: bones(v.bones), ...v.light,
  };
  for (const [k, val] of Object.entries(props)) res = setProp(text, res, k, val);
  text = `${text.slice(0, resStart)}${res.body.trimEnd()}\n`;
  writeFileSync(join(THEME_DIR, `slice_${name}.tres`), text);
  console.log(`slice_${name}.tres`);
}
