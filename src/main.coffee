{exec} = require 'child_process'
path = require 'path'
async = require 'async'
layout = require 'layout'
tinycolor = require 'tinycolor2'
imColors = require 'imagemagick-colors'
temp = require 'temp'
{compare} = require 'file-compare'

MIN_AREA_FOR_HUGE_IMAGES = 400000
MAX_AREA_FOR_SMALL_IMAGES = 4000
MAX_LAYERS_IN_SMALL_PSD = 50
MIN_LAYERS_IN_SPRITE = 30
TRANSPARENT_COLOR = if process.platform is 'darwin' then 'xc:rgba\\(0,0,0,0\\)' else 'xc:rgba(0,0,0,0)'

module.exports = class ImageProcessor
  constructor: ({ images, @convertPath }) ->
    @convertPath ?= 'convert'

    @uniques = {}
    @duplicates = {}

    @spritesheetFiles = []

    @results = {}
    @imagesById = {}
    for image in images
      @imagesById[image.id] = image
      @results[image.id] =
        id: image.id
        type: 'file'

  process: (callback) ->
    # duplicates
    async.eachSeries Object.keys(@results), (id, done) =>
      result = @results[id]

      @_compareLayer @imagesById[result.id], (original) =>
        if original
          result.type = 'duplicate'
          result.original = original
        done()
    , (err) =>
      # simple fills
      toTest = @_getFileResults()
      async.eachLimit toTest, 20, (id, done) =>
        res = @results[id]
        @_testSimpleFill @imagesById[id], (err, fill) =>
          if not err and fill
            if fill.a is 0
              res.type = 'blank'
            else
              res.type = 'color'
              res.color = fill
          done()
      , (err) =>
        # finally sprites
        @_generateSprites (err) =>
          callback null,
            results: @results
            files: @spritesheetFiles.concat @_getFileResults().map (id) => @imagesById[id].file

  _getFileResults: ->
    Object.keys(@results).filter (id) => @results[id].type is 'file'

  _compareLayer: (tested, callback) ->
    tested.dimensions ?= "#{tested.width}x#{tested.height}"

    suspects = @uniques[tested.dimensions]?.filter (suspect) -> suspect.size is tested.size

    if not suspects or suspects.length is 0
      @addToUniques tested
      callback(null)
    else
      testFunctions = []

      for suspect in suspects
        testFunctions.push @createComparer tested, suspect

      async.series testFunctions, (found) =>
        if found
          callback found.id
        else
          @addToUniques tested
          callback null

  createComparer: (tested, unique) ->
    (done) ->
      compare unique.file, tested.file, (copied, err) ->
        if err or not copied
          done null, null
        else
          done unique, null

  addToUniques: (original) ->
    @uniques[original.dimensions] ?= []
    @uniques[original.dimensions].push original

  _testSimpleFill: (image, callback) ->
    test = @_generateConvertTask @_generatePaletteArguments image
    test (err, output) =>
      [count, color] = output.split '='
      if color
        normalized = imColors[color.toLowerCase()]
        if normalized
          color = normalized
        if err?.stderr?.indexOf('colors.xml') isnt -1
          err = false

        if not err and parseInt(count, 10) is 1
          callback null, tinycolor(color.replace('srgb', 'rgb')).toRgb()
        else
          callback err
      else
        callback err

  _generatePaletteArguments: (image) ->
    "\"#{image.file}\" -unique-colors -colorspace sRGB -format \"%w=%[pixel:p{0,0}]\" info:"

  _generateSpriteArguments: (info) ->
    args = ["-size #{info.width}x#{info.height} " + TRANSPARENT_COLOR]
    for item in info.items
      args.push "\"#{@imagesById[item.meta].file}\" -geometry +#{item.x}+#{item.y} -composite"
    args.join ' '

  _generateConvertTask: (args) ->
    (done) =>
      exec "\"#{@convertPath}\" #{args}", {}, (error, stdout, stderr) ->
        done((if error or stderr then {error: error, stdout: stdout, stderr: stderr } else null), stdout)

  _generateSprites: (callback) ->
    images = @_getFileResults().map (id) => @imagesById[id]

    images = images.filter (image) -> (image.width * image.height) < MIN_AREA_FOR_HUGE_IMAGES

    if images.length > 1
      if images.length <= MAX_LAYERS_IN_SMALL_PSD
        spriteSheets = all: images
      else
        spriteSheets =
          text: []
          small: []
          shapes: []
          others: []

        for image in images
          imageArea = image.width * image.height

          if imageArea < MAX_AREA_FOR_SMALL_IMAGES
            spriteSheets.small.push image
          else if image.type is 'text'
            spriteSheets.text.push image
          else if image.type is 'shape'
            spriteSheets.shapes.push image
          else
            spriteSheets.others.push image

        unassignedImages = []

        for type, imgs of spriteSheets
          if imgs.length is 0
            delete spriteSheets[type]
          else if imgs.length < MIN_LAYERS_IN_SPRITE
            unassignedImages = unassignedImages.concat spriteSheets[type]
            delete spriteSheets[type]

        if unassignedImages.length > 0
          spriteSheets['sprites'] = unassignedImages

      if spriteSheets and Object.keys(spriteSheets).length > 0
        temp.mkdir 'spritesheets', (err, tmpDir) =>
          if err
            callback null
            return

          magickTasks = []
          positionsCache = {}

          for type, imgs of spriteSheets
            sheet = layout 'binary-tree'
            for img in imgs
              sheet.addItem
                height: img.height
                width: img.width
                meta: img.id
            info = sheet.export()

            for item in info.items
              positionsCache[item.meta] = item

            magickTasks.push "#{@_generateSpriteArguments(info)} #{path.join tmpDir, type + '.png'}"

          async.parallel magickTasks.map(@_generateConvertTask, this), (err) =>
            if err
              callback err
            else
              for type, imgs of spriteSheets
                imagePath = path.resolve tmpDir, type + '.png'
                @spritesheetFiles.push imagePath
                for img in imgs
                  res = @results[img.id]
                  res.type = 'sprite'
                  res.sprite =
                    file: imagePath
                    x: positionsCache[img.id].x
                    y: positionsCache[img.id].y
              callback null
      else
        callback null
    else
      callback null
