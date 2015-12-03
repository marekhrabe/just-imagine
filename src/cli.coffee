ImageProcessor = require './main'

process.stdin.resume()
process.stdin.setEncoding 'utf8'

stdinData = ''

process.stdin.on 'data', (chunk) ->
  stdinData += chunk

process.stdin.on 'end', ->
  processor = new ImageProcessor(images: JSON.parse(stdinData))
  processor.process (err, res) ->
    if err
      console.log JSON.stringify(error: err.toString())
      return process.exit(1)

    console.log JSON.stringify(res)
    process.exit(0)
