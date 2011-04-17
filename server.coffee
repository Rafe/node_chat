HOST = null
PORT = 8001
MESSAGE_BACKLOG = 200
SESSION_TIMEOUT = 60*1000

fu = require './fu'
sys = require 'sys'
url = require 'url'
qs = require 'querystring'

starttime = (new Date()).getTime()

mem = process.memoryUsage()

setInterval ->
  mem = process.memoryUsage()
, 10*1000

channel = new ()->
  messages = []
  callbacks = []

  @appendMessage = (nick,type,text)->
    m =
      nick: nick
      type: type
      text: text
      timestamp: (new Date()).getTime()

    switch type
      when 'msg'
        sys.puts "<#{nick}>#{text}"
      when 'join'
        sys.puts "#{nick} join"
      when 'part'
        sys.puts "#{nick} part"

    messages.push m

    callbacks.shift().callback([m]) while callbacks.length > 0
    messages.shift() while messages.length > MESSAGE_BACKLOG

  @query = (since,callback) ->
    matching = []
    for message in messages
      matching.push message if message.timestamp > since

    if matching.length isnt 0
      callback matching
    else
      callbacks.push
        timestamp: new Date()
        callback: callback

  setInterval ->
    now = new Date()
    while callbacks.length > 0 and now - callbacks[0].timestamp > 30*1000
      callbacks.shift().callback []
  , 3000
  
  this

sessions = {}

createSession = (nick)->
  return null if nick.length > 50
  return null if /[^\w_\-^!]/.exec nick

  for id,session of sessions
    return null if session and session.nick is nick
  session =
    nick: nick
    id: Math.floor(Math.random() * 99999999999).toString()
    timestamp: new Date()
    poke:()->
      session.timestamp = new Date()
    destroy: ()->
      channel.appendMessage session.nick, 'part'
      delete sessions[session.id]
  sessions[session.id] = session
  session


setInterval ->
  now = new Date()
  for id,session of sessions
    continue if not session
    session.destroy() if now - session.timestamp > SESSION_TIMEOUT
, 1000

fu.listen(Number(process.env.PORT or PORT), HOST)

fu.get '/', fu.staticHandler 'index.html'
fu.get '/style.css', fu.staticHandler 'style.css'
fu.get '/client.js', fu.staticHandler 'client.js'
fu.get '/jquery-1.5.2.min.js', fu.staticHandler 'jquery-1.5.2.min.js'

fu.get '/who', (req,res) ->
  nicks = []
  for id,session of sessions
    nicks.push session.nick

  res.simpleJSON 200,
    nicks: nicks
    rss: mem.rss

fu.get '/join', (req,res) ->
  nick = qs.parse(url.parse(req.url).query).nick
  if nick is null or nick.length is 0
    res.simpleJSON 400, {error: 'Bad nick'}
    return
  session = createSession nick
  if session is null
    res.simpleJSON 400, {error: 'Nick in use'}
    return

  sys.puts "conntection #{nick} @ #{res.connection.remoteAddress}"

  channel.appendMessage session.nick, 'join'
  res.simpleJSON 200,
    id: session.id
    nick: session.nick
    rss: mem.rss
    starttime: starttime

fu.get '/part', (req,res) ->
  id = qs.parse(url.parse(req.url).query).id
  if id and sessions[id]
    sessions[id].destroy()

  res.simpleJSON 200, {res: mem.rss}

fu.get '/recv', (req,res) ->
  if not qs.parse(url.parse(req.url).query).since
    res.simpleJSON 400, {error:'Must supply since parameter'}
    return

  id = qs.parse(url.parse(req.url).query).id
  session = null
  if id and sessions[id]
    session = sessions[id]
    session.poke()

  since = parseInt(qs.parse(url.parse(req.url).query).since,10)

  channel.query since,(messages) ->
    session.poke() if session
    res.simpleJSON 200, {messages: messages, rss: mem.rss}

fu.get '/send', (req, res) ->
  id = qs.parse(url.parse(req.url).query).id
  text = qs.parse(url.parse(req.url).query).text

  session = sessions[id]
  if not session and not text
    res.simpleJSON 400, error: 'No such session id'
    return

  session.poke()

  channel.appendMessage(session.nick, 'msg', text)
  res.simpleJSON 200, {rss:mem.rss}
