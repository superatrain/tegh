EventEmitter = require('events').EventEmitter
util = require 'util'
require 'sugar'
glob = require 'glob'
ansi = require 'ansi'
readline = require 'readline'
ConstructClient = require './construct/client'
ServiceSelector = require './service_selector'
fs = require "fs-extra"
touch = require "touch"
path = require ("flavored-path")

stdout = process.stdout
stdin = process.stdin

clear = -> `util.print("\u001b[2J\u001b[0;0f")`

getUserHome = ->
  process.env.HOME || process.env.HOMEPATH || process.env.USERPROFILE

class CliConsole
  historyPath: "#{getUserHome()}/.construct_history"

  constructor: (@src) ->
    @cursor = ansi(stdout)

    @rl = readline.createInterface
      input: stdin
      output: stdout
      completer: @src._autocomplete
      terminal: true

    # loading the user's readline history
    touch.sync @historyPath
    @rl.history = (fs.readFileSync(@historyPath)).toString().split("\n")

    clear()
    @render(false)
    @rl.setPrompt("> ", 2)
    @rl.prompt()

    @rl.on "line", @_onLine
    @rl.on 'SIGINT', @_onSIGINT
    process.on 'exit', @_onExit
    stdout.on 'resize', @render
    stdin.on 'data', @_onData

  _onLine: (line) =>
    @src._parseLine(line)
    @render(false)
    @rl.prompt()

  _onSIGINT: =>
    if @rl.line == ""
      process.exit()
    else
      stdout.write("\n")
      @rl.line = ""
      @rl.prompt()

  _onData: (char) =>
    process.exit() if char == `'\4'`

  _onExit: =>
    fs.writeFileSync @historyPath, @rl.history.join("\n")
    stdout.write("\n")

  updateSize: ->
    @width = stdout.columns
    @height = stdout.rows-2

  render: (restore = true) =>
    stdin.pause()
    @updateSize()

    header = @src._header()
    c = @cursor

    c.savePosition().goto(0, 0)
    c.black().bg.white()
    c.write(header.padRight(" ", @width - header.length))
    c.reset().bg.reset()

    c.goto(0, @height+2).show()
    c.restorePosition() if restore
    stdin.resume()


class QueueTea
  commands: require './help'

  constructor: ->
    new ServiceSelector().on "select", @_onServiceSelect
    @_sensors = {}



  _onServiceSelect: (service) =>
    clear()
    stdout.write "Connecting to #{service.addresses.first()}:#{service.port}..."
    @client = new ConstructClient(service.addresses.first(), service.port)
      .on("connect", @_onConnect)
      .on("sensor_changed", @_onSensorChanged)
      .on("jobs", @_onJobsList)
      .on("job_upload_complete", @_onJobUploadComplete)
      .on("close", @_onClose)
    # @client = new ConstructClient(service.host[0..-2], service.port)

  _onConnect: =>
    @cli = new CliConsole(@)

  _onSensorChanged: (data) =>
    @_sensors[data.name] = data.value
    @cli.render()

  _onClose: =>
    console.log("Server disconnected.")
    process.exit()

  _onJobsList: (jobs) =>
    @cli.rl.pause()
    stdout.write("\r")
    console.log "Print Jobs:\n"
    for job, i in jobs
      name = job.file_name
      id = job.id.toString()
      prefix = "  #{i}) #{name} "
      suffix = "job ##{job.id.pad(5)}  "
      console.log "#{prefix.padRight(".", @cli.width - suffix.length - prefix.length - 1)} #{suffix}"
    console.log ""
    @cli.rl.prompt()
    @cli.rl.resume()

  _onJobUploadComplete: (statusCode) =>
      @cli.rl.pause()
      if statusCode = 200
        status = "Job added."
      else
        status = "Error adding job."
      process.stdout.write("\r" + status + "\n")
      @cli.rl.prompt()
      @cli.rl.resume()


  _header: ->
    fields = []
    for k, v of @_sensors
      fields.push "#{k.capitalize()}: #{v}\u00B0C"
    fields.join("  ")

  _append: (s, prefix = "") ->
    stdout.write(prefix + s + "\n")

  _parseLine: (line) =>
    line = line.toString()
    words = line.split(/\s/)[0]
    cmd = words.shift()
    if cmd == "help" then @_appendHelp()
    else if cmd == "exit" then return process.exit()
    else if @commands[cmd]? then @client.send(line)
    else
      @_append """
        Error: '#{cmd}' is not a valid command.
        Try typing 'help' for more info.
      """
    @cli.render()

  _appendHelp: ->
    help = """
      Help
      #{"".padLeft("-", @cli.width)}
      The following commands are available on your printer:\n\n
    """
    # The following commands are available on your printer,
    # to learn more about a specific command type help <CMD>\n\n
    # """

    for cmd, data of @commands
      desc = data.description.split("\n")
      help += "- #{cmd.padRight(" ", 12 - cmd.length)} - #{desc.shift()}\n"
      help += "#{d.padLeft(" ", 12+5)}\n" for d in desc
    @_append("")
    @_append(help)
    @_append("")

  _autocomplete: (line) =>
    out = []
    words = line.split(" ")
    if words.length == 1
      for cmd, data of @commands
        out.push cmd if cmd.indexOf(line) == 0
      out[0] = out[0] + " " if out.length == 1

    if words[0] == "add_job"
      # Creating a glob to find files that start with the path
      # the user is building.
      relative = (words[1]||"").indexOf("~") == 0
      globPath = (words[1..]||[""]).join(" ") + "*"
      globPath = path.get globPath if relative

      out = glob(globPath, sync: true)

      if out.length == 1
        @cli.rl.line = "add_job /" if relative
        out[0] = "add_job #{out[0]}"

    return [out, line]

new QueueTea()