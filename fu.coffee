createServer = require('http').createServer
readFile = require('fs').readFile
sys = require 'sys'
url = require 'url'
DEBUG =true

fu = exports

NOT_FOUND = "Not Found\n"

notFound = (req,res) ->
  res.writeHead 404,
    "Content-Type":"text/plain"
    "Content-Length":NOT_FOUND.length
  res.end NOT_FOUND

getMap = {}

fu.get = (path,handler)->
  getMap[path] = handler

server = createServer (req,res) ->
  if req.method is "GET" or req.method is "HEAD"
    handler = getMap[url.parse(req.url).pathname] or notFound

    res.simpleText = (code,body)->
      res.writeHead code,
        "Content-Type": "text/plain"
        "Content-Length": body.length
      res.end body

    res.simpleJSON = (code,obj)->
      body = new Buffer JSON.stringify(obj)
      res.writeHead code,
        "Content-Type": "text/json"
        "Content-Length": body.length
        "Cache-Control": "private"
      res.end body

    handler req,res

fu.listen = (port,host)->
  server.listen port,host
  sys.puts "Server at http://#{host||'127.0.0.1'}:#{port.toString()}/"

fu.close = ()->
  server.close()

extname = (path)->
  index = path.lastIndexOf "."
  if index < 0 then "" else path.substring index 

fu.staticHandler = (filename)->
  body = undefined
  headers=undefined
  content_type = fu.mime.lookupExtension extname(filename)

  loadResponseData = (callback)->
    if body and headers and not DEBUG
      callback()
      return

    sys.puts "loading #{filename}"
    readFile filename, (err,data)->
      if err
        sys.puts "Error loading #{filename}"
      else
        body = data
        headers =
          "Content-Type": content_type
          "Content-Length": body.length
        if not DEBUG
          headers["Cache-Control"] = "public"
        sys.puts("static file #{filename} loaded")
        callback()

  return (req,res)->
    loadResponseData ->
      res.writeHead 200,headers
      res.end if req.method is "HEAD" then "" else body

fu.mime =
  lookupExtension : (ext,fallback)->
    return fu.mime.TYPES[ext.toLowerCase()] or fallback or 'application/octet-stream'
  TYPES :
    ".js": "application/javascript"
    ".html": "text/html"
    ".jpg": "image/jpeg"
    ".css": "text/css"
