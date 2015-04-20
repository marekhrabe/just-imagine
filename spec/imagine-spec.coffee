path = require 'path'

ImageProcessor = require '..'

processor = null
results = null

imagesDir = path.join __dirname, 'images'

twoAvocados = [
  {
    id: 1
    width: 200
    height: 184
    file: path.join imagesDir, 'avocode.png'
  }
  {
    id: 2
    width: 200
    height: 184
    file: path.join imagesDir, 'avocode.png'
  }
]

source = {
  id: 5
  width: 74
  height: 42
  file: path.join imagesDir, 'source.png'
}

kitten = {
  id: 10
  width: 200
  height: 200
  file: path.join imagesDir, 'kitten.png'
}

describe 'Just imagine', ->
  beforeEach ->
    results =  null

  describe 'duplicates', ->
    it 'should mark two identical images as duplicates', ->
      processor = new ImageProcessor
        images: twoAvocados
      processor.process (err, res) -> results = res
      waitsFor -> results

      runs ->
        expect(results.results[2].type).toEqual 'duplicate'
        expect(results.results[2].original).toEqual 1

    it 'should not return extra file for duplicate', ->
      processor = new ImageProcessor
        images: twoAvocados
      processor.process (err, res) -> results = res
      waitsFor -> results

      runs ->
        expect(results.files.length).toEqual 1

  describe 'color fills', ->

    it 'should mark all-white image as a color fill', ->
      processor = new ImageProcessor
        images: [
          id: 1
          width: 400
          height: 300
          file: path.join imagesDir, 'all-white.png'
          type: 'shape'
        ]
      processor.process (err, res) -> results = res
      waitsFor -> results

      runs ->
        expect(results.results['1'].type).toEqual 'color'

    it 'should return no files when there is only color fills', ->
      processor = new ImageProcessor
        images: [
          id: 1
          width: 400
          height: 300
          file: path.join imagesDir, 'all-white.png'
          type: 'shape'
        ]
      processor.process (err, res) -> results = res
      waitsFor -> results

      runs ->
        expect(results.files.length).toEqual 0

    it 'should not do anything for non-color fill image', ->
      processor = new ImageProcessor
        images: [
          id: 1
          width: 200
          height: 184
          file: path.join imagesDir, 'avocode.png'
        ]
      processor.process (err, res) -> results = res
      waitsFor -> results

      runs ->
        expect(results.results[1].type).toEqual 'file'
        expect(results.files.length).toEqual 1


  describe 'sprite sheets', ->
    it 'should not be generated for single image', ->
      processor = new ImageProcessor
        images: [
          id: 1
          width: 200
          height: 184
          file: path.join imagesDir, 'avocode.png'
        ]
      processor.process (err, res) -> results = res
      waitsFor -> results

      runs ->
        expect(results.results[1].type).toEqual 'file'
        expect(results.files.length).toEqual 1

    it 'should be generated for more images', ->
      processor = new ImageProcessor
        images: twoAvocados.concat [
          source
          kitten
        ]
      processor.process (err, res) -> results = res
      waitsFor -> results

      runs ->
        expect(results.results[1].type).toEqual 'sprite'
        expect(results.files.length).toEqual 1

    # todo - test with more images (icon set) to see how they would be divided into few

  describe 'blank images', ->
    it 'should mark blank images', ->
      processor = new ImageProcessor
        images: [
          id: 1
          width: 400
          height: 400
          file: path.join imagesDir, 'all-transparent.png'
          type: 'shape'
        ]
      processor.process (err, res) -> results = res
      waitsFor -> results

      runs ->
        expect(results.results['1'].type).toEqual 'blank'
