local spr = app.activeSprite
if not spr then return print('No active sprite') end

-- Extract the current path and filename of the active sprite
local local_path, title, extension = spr.filename:match("^(.+[/\\])(.-)(%.[^.]*)$")

-- Construct export path by prefixing the current .aseprite file path
local export_path = local_path .. "images/"
local_path = export_path

local sprite_name = app.fs.fileTitle(app.activeSprite.filename)

function layer_export(layer)
  local fn = local_path .. "/" .. layer.name
  app.command.ExportSpriteSheet{
      ui=false,
      type=SpriteSheetType.HORIZONTAL,
      textureFilename=fn .. '.png',
      dataFormat=SpriteSheetDataFormat.JSON_ARRAY,
      layer=layer.name,
      trim=true,
  }
end

local asset_path = local_path .. '/' ---.. sprite_name .. '/'

function do_animation_export()
  for i,tag in ipairs(spr.tags) do
    local fn =  asset_path .. sprite_name .. "_" .. tag.name
    app.command.ExportSpriteSheet{
      ui=false,
      type=SpriteSheetType.HORIZONTAL,
      textureFilename=fn .. '.png',
      dataFormat=SpriteSheetDataFormat.JSON_ARRAY,
      tag=tag.name,
      listLayers=false,
      listTags=false,
      listSlices=false,
    }
  end
end

-- Export all visible layers instead of just the active layer
for i, layer in ipairs(spr.layers) do
  if layer.isVisible then
    layer_export(layer)
  end
end

-- The animation export remains as it was, based on your condition
if string.find(sprite_name, "player") then
  -- print("player export")
  do_animation_export()
end