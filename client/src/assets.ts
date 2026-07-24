// Central asset registry - every runtime model URL in ONE place. All loaders
// (CharacterModel, CashBundleView, PropLibrary) read their paths from here
// instead of hardcoding them, so swapping in new assets (e.g. Blender-MCP-
// authored models) is a single-file change. This is the seam the Blender asset
// pipeline plugs into: regenerate the .glb under client/public/models/ and, if
// the naming changes, update only the functions below.
export const MODEL_PATHS = {
  cashBundle: "/models/cashbundle.glb",
  character: (variant: string) => `/models/characters/${variant}.glb`,
  prop: (name: string) => `/models/props/${name}.glb`,
} as const;
