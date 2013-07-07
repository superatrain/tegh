#!/usr/bin/env coffee
path = require('path')
sys = require('sys')
spawn = require('child_process').spawn
_execSync = require('exec-sync')
stdout = process.stdout
glob = require('glob')
fs = require('fs')
require("sugar")

fedoraRoot = path.resolve __dirname, "fedora-src"
specFile = path.resolve fedoraRoot, 'SPECS', 'tegh.spec'

console.log(fedoraRoot)

puts = (error, stdout, stderr, cb) ->
  sys.puts(stdout)
  sys.puts(stderr)
  cb?()

spw = (cmd, args, cb) ->
  console.log "#{cmd} #{args.map((s) -> "\"#{s}\"").join(' ')}"
  proc = spawn cmd, args

  printStream = (stream) ->
    proc[stream].on 'data', (data) -> stdout.write data

  printStream(stream) for stream in ['stdout', 'stderr']

  proc.on "exit", cb if cb?

execSync = (cmd) -> console.log require('exec-sync')(cmd)

args = [
  "-ba",
  "--define", "_topdir #{fedoraRoot}",
  "--define", "_datadir /usr/share",
  "--define", "_bindir /usr/bin",
  "--target",
  "noarch-redhat-linux",
  specFile
]


class FedoraBuild
  run: ->
    previousRpm = @_findRpm()
    fs.unlinkSync previousRpm if previousRpm?
    spw "rpmbuild", args, @postBuild
# mv ./fedora-src/SOURCES/tegh-master.tar.gz ./fedora-src/SOURCES/master.tar.gz
# "
#   rpmbuild #{defines} -ba #{specFile}
# """, postInstall

  _findRpm: -> glob.sync("fedora-src/RPMS/noarch/tegh-*.rpm")[0]


  postBuild: =>
    @package = @_findRpm()
    console.log @package
    execSync "scp #{@package} fedora-ec2:~/stuff"
    console.log @package


new FedoraBuild().run()
