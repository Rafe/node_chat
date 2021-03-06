CONFIG =
  debug: false
  nick: "#"
  id: null
  last_message_time: 1
  focus: true
  unread: 0

nicks = []

Date::toRelativeTime = (now_threshold) ->
  delta = new Date() - this

  now_threshold = parseInt(now_threshold, 10)

  now_threshold = 0 if isNaN(now_threshold)

  return 'Just now' if delta <= now_threshold

  units = null
  conversions =
    millisecond: 1
    second: 1000
    minute: 60
    hour:   60
    day:    24
    month:  30
    year:   12

  for key,conversion of conversions
    break if delta < conversion
    units = key
    delta = delta / conversion

  delta = Math.floor delta
  units += "s" if delta isnt 1
  [delta, units].join " "

Date.fromString = (str)->
  new Date(Date.parse(str))

updateUsersLink = () ->
  t = nicks.length.toString() + " user"
  t += "s" if nicks.length isnt 1
  $("#usersLink").text t

userJoin = (nick, timestamp) ->
  #put it in the stream
  addMessage(nick, "joined", timestamp, "join")
  #if we already know about this user, ignore it
  for name in nicks
    return if name is nick
  #otherwise, add the user to the list
  nicks.push nick
  #update the UI
  updateUsersLink()

#handles someone leaving
userPart = (nick, timestamp)->
  #put it in the stream
  addMessage(nick, "left", timestamp, "part")
  #remove the user from the list
  for name in nicks
    if name is nick
      nicks.splice(i,1) # remove target nickname by calling splice()
      break
  #update the UI
  updateUsersLink()

util =
  urlRE: /https?:\/\/([-\w\.]+)+(:\d+)?(\/([^\s]*(\?\S+)?)?)?/g

  #html sanitizer 
  toStaticHTML: (inputHtml) ->
    inputHtml = inputHtml.toString()
    return inputHtml.replace(/&/g, "&amp;")
                    .replace(/</g, "&lt;")
                    .replace(/>/g, "&gt;")

  #pads n with zeros on the left,
  #digits is minimum length of output
  #zeroPad(3, 5); returns "005"
  #zeroPad(2, 500); returns "500"
  zeroPad: (digits, n) ->
    n = n.toString()
    n = '0' + n while n.length < digits
    return n

  #it is almost 8 o'clock PM here
  #timeString(new Date) returns "19:49"
  timeString: (date) ->
    minutes = date.getMinutes().toString()
    hours = date.getHours().toString()
    this.zeroPad(2, hours) + ":" + this.zeroPad(2, minutes)

  #does the argument only contain whitespace?
  isBlank: (text) ->
    blank = /^\s*$/
    text.match(blank) isnt null

#used to keep the most recent messages visible
scrollDown = () ->
  window.scrollBy(0, 100000000000000000)
  $("#entry").focus()

#inserts an event into the stream for display
#the event may be a msg, join or part type
#from is the user, text is the body and time is the timestamp, defaulting to now
#_class is a css class to apply to the message, usefull for system events
addMessage = (from, text, time, _class) ->
  return if text is null

  if time is null
    #if the time is null or undefined, use the current time.
    time = new Date()
  if (time instanceof Date) is false
    # if it's a timestamp, interpret it
    time = new Date(time)

  #every message you see is actually a table with 3 cols:
  #  the time,
  #  the person who caused the event,
  #  and the content
  messageElement = $(document.createElement("table"))

  messageElement.addClass "message"
  messageElement.addClass(_class) if _class

  # sanitize
  text = util.toStaticHTML(text)

  #If the current user said this, add a special css class
  nick_re = new RegExp(CONFIG.nick)

  messageElement.addClass "personal" if nick_re.exec(text)

  #replace URLs with links
  text = text.replace(util.urlRE, '<a target="_blank" href="$&">$&</a>')

  content = """<tr>
              <td class='date'>#{util.timeString(time)}</td>
              <td class='nick'>#{ util.toStaticHTML(from)}</td>
              <td class='msg-text'>#{text}</td>
              </tr>"""
  messageElement.html(content)

  #the log is the stream that we view
  $("#log").append(messageElement)

  #always view the most recent message when it is added
  scrollDown()

updateRSS = ()->
  bytes = parseInt(rss)
  if bytes
    megabytes = bytes / (1024*1024)
    megabytes = Math.round(megabytes*10)/10
    $("#rss").text(megabytes.toString())

updateUptime = ()->
  $("#uptime").text(starttime.toRelativeTime()) if starttime

transmission_errors = 0
first_poll = true

#process updates if we have any, request updates from the server,
# and call again with response. the last part is like recursion except the call
# is being made from the response handler, and not at some point during the
# function's execution.
longPoll = (data)->
  if transmission_errors > 2
    showConnect()
    return

  if data and data.rss
    rss = data.rss
    updateRSS()

  #process any updates we may have
  #data will be null on the first call of longPoll
  if data and data.messages
    for message in data.messages

      #track oldest message so we only request newer messages from server
      if message.timestamp > CONFIG.last_message_time
        CONFIG.last_message_time = message.timestamp

      #dispatch new messages to their appropriate handlers
      switch message.type
        when "msg"
          CONFIG.unread++ if not CONFIG.focus
          addMessage(message.nick, message.text, message.timestamp)

        when "join" then userJoin(message.nick, message.timestamp)
        when "part" then userPart(message.nick, message.timestamp)
    #update the document title to include unread message count if blurred
    updateTitle()

    #only after the first request for messages do we want to show who is here
    if first_poll
      first_poll = false
      who()

  #make another request
  $.ajax
    cache: false
    type: "GET"
    url: "/recv"
    dataType: "json"
    data: { since: CONFIG.last_message_time, id: CONFIG.id }
  .done (data) ->
    transmission_errors = 0
    #if everything went well, begin another request immediately
    #the server will take a long time to respond
    #how long? well, it will wait until there is another message
    #and then it will return it to us and close the connection.
    #since the connection is closed when we get data, we longPoll again
    longPoll(data)
  .fail ()->
    addMessage("", "long poll error. trying again...", new Date(), "error")
    transmission_errors += 1
    #don't flood the servers on error, wait 10 seconds before retrying
    setTimeout(longPoll, 10*1000)

#submit a new message to the server
send = (msg) ->
  if CONFIG.debug is false
    #XXX should be POST
    #XXX should add to messages immediately
    jQuery.get("/send", {id: CONFIG.id, text: msg},
      (data)->
        true
    ,"json")

#Transition the page to the state that prompts the user for a nickname
showConnect = () ->
  $("#connect").show()
  $("#loading").hide()
  $("#toolbar").hide()
  $("#nickInput").focus()

#transition the page to the loading screen
showLoad = ()->
  $("#connect").hide()
  $("#loading").show()
  $("#toolbar").hide()

#transition the page to the main chat view, putting the cursor in the textfield
showChat = (nick) ->
  $("#toolbar").show()
  $("#entry").focus()

  $("#connect").hide()
  $("#loading").hide()

  scrollDown()

#we want to show a count of unread messages when the window does not have focus
updateTitle = ()->
  if CONFIG.unread
    document.title = "(#{CONFIG.unread.toString()}) node chat"
  else
    document.title = "node chat"

#daemon start time
starttime = undefined
#daemon memory usage
rss = undefined

#handle the server's response to our nickname and join request
onConnect = (session) ->
  if session.error
    alert("error connecting: " + session.error)
    showConnect()
    return

  CONFIG.nick = session.nick
  CONFIG.id   = session.id
  starttime   = new Date(session.starttime)
  rss         = session.rss
  updateRSS()
  updateUptime()

  #update the UI to show the chat
  showChat(CONFIG.nick)

  #listen for browser events so we know to update the document title
  $(window).bind "blur", () ->
    CONFIG.focus = false
    updateTitle()

  $(window).bind "focus", () ->
    CONFIG.focus = true
    CONFIG.unread = 0
    updateTitle()

#add a list of present chat members to the stream
outputUsers = () ->
  nick_string = if nicks.length > 0 then nicks.join(", ") else "(none)"
  addMessage("users:", nick_string, new Date(), "notice")
  return false

#get a list of the users presently in the room, and add it to the stream
who = ()->
  jQuery.get "/who", {},  (data, status) ->
    return if status isnt "success"
    nicks = data.nicks
    outputUsers()
  ,"json"

$ ()->
  #submit new messages when the user hits enter if the message isnt blank
  $("#entry").keypress (e)->
    return if e.keyCode isnt 13 #return
    msg = $("#entry").attr("value").replace("\n", "")
    send msg if not util.isBlank(msg)
    $("#entry").attr("value", "") # clear the entry field.

  $("#usersLink").click(outputUsers)

  #try joining the chat when the user clicks the connect button
  $("#connectButton").click ()->
    #lock the UI while waiting for a response
    showLoad()
    nick = $("#nickInput").attr("value")

    #dont bother the backend if we fail easy validations
    if nick.length > 50
      alert("Nick too long. 50 character max.")
      showConnect()
      return false

    #more validations
    if /[^\w_\-^!]/.exec(nick)
      alert("Bad character in nick. Can only have letters, numbers, and '_', '-', '^', '!'")
      showConnect()
      return false

    #make the actual join request to the server
    $.ajax
      cache: false
      type: "GET" # XXX should be POST
      dataType: "json"
      url: "/join"
      data: { nick: nick }
      error:()->
        alert("error connecting to server")
        showConnect()
      success: onConnect

    false

  # update the daemon uptime every 10 seconds
  setInterval ()->
    updateUptime()
  , 10*1000

  if CONFIG.debug
    $("#loading").hide()
    $("#connect").hide()
    scrollDown()
    return

  # remove fixtures
  $("#log table").remove()

  #begin listening for updates right away
  #interestingly, we don't need to join a room to get its updates
  #we just don't show the chat stream to the user until we create a session
  longPoll()

  showConnect()

#if we can, notify the server that we're going away.
$(window).unload ()->
  jQuery.get("/part", {id: CONFIG.id},  (data) { }, "json")
