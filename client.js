(function() {
  var CONFIG, addMessage, first_poll, longPoll, nicks, onConnect, outputUsers, rss, scrollDown, send, showChat, showConnect, showLoad, starttime, transmission_errors, updateRSS, updateTitle, updateUptime, updateUsersLink, userJoin, userPart, util, who;
  CONFIG = {
    debug: false,
    nick: "#",
    id: null,
    last_message_time: 1,
    focus: true,
    unread: 0
  };
  nicks = [];
  Date.prototype.toRelativeTime = function(now_threshold) {
    var conversion, conversions, delta, key, units;
    delta = new Date() - this;
    now_threshold = parseInt(now_threshold, 10);
    if (isNaN(now_threshold)) {
      now_threshold = 0;
    }
    if (delta <= now_threshold) {
      return 'Just now';
    }
    units = null;
    conversions = {
      millisecond: 1,
      second: 1000,
      minute: 60,
      hour: 60,
      day: 24,
      month: 30,
      year: 12
    };
    for (key in conversions) {
      conversion = conversions[key];
      if (delta < conversion) {
        break;
      }
      units = key;
      delta = delta / conversion;
    }
    delta = Math.floor(delta);
    if (delta !== 1) {
      units += "s";
    }
    return [delta, units].join(" ");
  };
  Date.fromString = function(str) {
    return new Date(Date.parse(str));
  };
  updateUsersLink = function() {
    var t;
    t = nicks.length.toString() + " user";
    if (nicks.length !== 1) {
      t += "s";
    }
    return $("#usersLink").text(t);
  };
  userJoin = function(nick, timestamp) {
    var name, _i, _len;
    addMessage(nick, "joined", timestamp, "join");
    for (_i = 0, _len = nicks.length; _i < _len; _i++) {
      name = nicks[_i];
      if (name === nick) {
        return;
      }
    }
    nicks.push(nick);
    return updateUsersLink();
  };
  userPart = function(nick, timestamp) {
    var name, _i, _len;
    addMessage(nick, "left", timestamp, "part");
    for (_i = 0, _len = nicks.length; _i < _len; _i++) {
      name = nicks[_i];
      if (name === nick) {
        nicks.splice(i, 1);
        break;
      }
    }
    return updateUsersLink();
  };
  util = {
    urlRE: /https?:\/\/([-\w\.]+)+(:\d+)?(\/([^\s]*(\?\S+)?)?)?/g,
    toStaticHTML: function(inputHtml) {
      inputHtml = inputHtml.toString();
      return inputHtml.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    },
    zeroPad: function(digits, n) {
      n = n.toString();
      while (n.length < digits) {
        n = '0' + n;
      }
      return n;
    },
    timeString: function(date) {
      var hours, minutes;
      minutes = date.getMinutes().toString();
      hours = date.getHours().toString();
      return this.zeroPad(2, hours) + ":" + this.zeroPad(2, minutes);
    },
    isBlank: function(text) {
      var blank;
      blank = /^\s*$/;
      return text.match(blank) !== null;
    }
  };
  scrollDown = function() {
    window.scrollBy(0, 100000000000000000);
    return $("#entry").focus();
  };
  addMessage = function(from, text, time, _class) {
    var content, messageElement, nick_re;
    if (text === null) {
      return;
    }
    if (time === null) {
      time = new Date();
    }
    if ((time instanceof Date) === false) {
      time = new Date(time);
    }
    messageElement = $(document.createElement("table"));
    messageElement.addClass("message");
    if (_class) {
      messageElement.addClass(_class);
    }
    text = util.toStaticHTML(text);
    nick_re = new RegExp(CONFIG.nick);
    if (nick_re.exec(text)) {
      messageElement.addClass("personal");
    }
    text = text.replace(util.urlRE, '<a target="_blank" href="$&">$&</a>');
    content = "<tr>\n<td class='date'>" + (util.timeString(time)) + "</td>\n<td class='nick'>" + (util.toStaticHTML(from)) + "</td>\n<td class='msg-text'>" + text + "</td>\n</tr>";
    messageElement.html(content);
    $("#log").append(messageElement);
    return scrollDown();
  };
  updateRSS = function() {
    var bytes, megabytes;
    bytes = parseInt(rss);
    if (bytes) {
      megabytes = bytes / (1024 * 1024);
      megabytes = Math.round(megabytes * 10) / 10;
      return $("#rss").text(megabytes.toString());
    }
  };
  updateUptime = function() {
    if (starttime) {
      return $("#uptime").text(starttime.toRelativeTime());
    }
  };
  transmission_errors = 0;
  first_poll = true;
  longPoll = function(data) {
    var message, rss, _i, _len, _ref;
    if (transmission_errors > 2) {
      showConnect();
      return;
    }
    if (data && data.rss) {
      rss = data.rss;
      updateRSS();
    }
    if (data && data.messages) {
      _ref = data.messages;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        message = _ref[_i];
        if (message.timestamp > CONFIG.last_message_time) {
          CONFIG.last_message_time = message.timestamp;
        }
        switch (message.type) {
          case "msg":
            if (!CONFIG.focus) {
              CONFIG.unread++;
            }
            addMessage(message.nick, message.text, message.timestamp);
            break;
          case "join":
            userJoin(message.nick, message.timestamp);
            break;
          case "part":
            userPart(message.nick, message.timestamp);
        }
      }
      updateTitle();
      if (first_poll) {
        first_poll = false;
        who();
      }
    }
    return $.ajax({
      cache: false,
      type: "GET",
      url: "/recv",
      dataType: "json",
      data: {
        since: CONFIG.last_message_time,
        id: CONFIG.id
      }
    }).done(function(data) {
      transmission_errors = 0;
      return longPoll(data);
    }).fail(function() {
      addMessage("", "long poll error. trying again...", new Date(), "error");
      transmission_errors += 1;
      return setTimeout(longPoll, 10 * 1000);
    });
  };
  send = function(msg) {
    if (CONFIG.debug === false) {
      return jQuery.get("/send", {
        id: CONFIG.id,
        text: msg
      }, function(data) {
        return true;
      }, "json");
    }
  };
  showConnect = function() {
    $("#connect").show();
    $("#loading").hide();
    $("#toolbar").hide();
    return $("#nickInput").focus();
  };
  showLoad = function() {
    $("#connect").hide();
    $("#loading").show();
    return $("#toolbar").hide();
  };
  showChat = function(nick) {
    $("#toolbar").show();
    $("#entry").focus();
    $("#connect").hide();
    $("#loading").hide();
    return scrollDown();
  };
  updateTitle = function() {
    if (CONFIG.unread) {
      return document.title = "(" + (CONFIG.unread.toString()) + ") node chat";
    } else {
      return document.title = "node chat";
    }
  };
  starttime = void 0;
  rss = void 0;
  onConnect = function(session) {
    if (session.error) {
      alert("error connecting: " + session.error);
      showConnect();
      return;
    }
    CONFIG.nick = session.nick;
    CONFIG.id = session.id;
    starttime = new Date(session.starttime);
    rss = session.rss;
    updateRSS();
    updateUptime();
    showChat(CONFIG.nick);
    $(window).bind("blur", function() {
      CONFIG.focus = false;
      return updateTitle();
    });
    return $(window).bind("focus", function() {
      CONFIG.focus = true;
      CONFIG.unread = 0;
      return updateTitle();
    });
  };
  outputUsers = function() {
    var nick_string;
    nick_string = nicks.length > 0 ? nicks.join(", ") : "(none)";
    addMessage("users:", nick_string, new Date(), "notice");
    return false;
  };
  who = function() {
    return jQuery.get("/who", {}, function(data, status) {
      if (status !== "success") {
        return;
      }
      nicks = data.nicks;
      return outputUsers();
    }, "json");
  };
  $(function() {
    $("#entry").keypress(function(e) {
      var msg;
      if (e.keyCode !== 13) {
        return;
      }
      msg = $("#entry").attr("value").replace("\n", "");
      if (!util.isBlank(msg)) {
        send(msg);
      }
      return $("#entry").attr("value", "");
    });
    $("#usersLink").click(outputUsers);
    $("#connectButton").click(function() {
      var nick;
      showLoad();
      nick = $("#nickInput").attr("value");
      if (nick.length > 50) {
        alert("Nick too long. 50 character max.");
        showConnect();
        return false;
      }
      if (/[^\w_\-^!]/.exec(nick)) {
        alert("Bad character in nick. Can only have letters, numbers, and '_', '-', '^', '!'");
        showConnect();
        return false;
      }
      $.ajax({
        cache: false,
        type: "GET",
        dataType: "json",
        url: "/join",
        data: {
          nick: nick
        },
        error: function() {
          alert("error connecting to server");
          return showConnect();
        },
        success: onConnect
      });
      return false;
    });
    setInterval(function() {
      return updateUptime();
    }, 10 * 1000);
    if (CONFIG.debug) {
      $("#loading").hide();
      $("#connect").hide();
      scrollDown();
      return;
    }
    $("#log table").remove();
    longPoll();
    return showConnect();
  });
  $(window).unload(function() {
    return jQuery.get("/part", {
      id: CONFIG.id
    }, data({}, "json"));
  });
}).call(this);
