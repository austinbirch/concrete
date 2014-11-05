# cli colors
colors = require 'colors'
git = require './git'
server = require './server'
exec = require('child_process').exec
spawn = require('child_process').spawn
mongo = require 'mongodb'
jobs = require './jobs'


parseSequence = (input) ->
  length = input.length
  return { cmd: input[length - 1], args: input.substring 2, length - 1 }

tokenize = (input, result = []) ->
  return [''] if input == ''

  input.replace /(\u001B\[.*?([@-~]))|([^\u001B]+)/g, (m) ->
    result.push m[0] == '\u001B' and parseSequence(m) or m

  return result


COLORS =
  0: '', 1: 'bold', 4: 'underscore', 5: 'blink',
  30: 'fg-black', 31: 'fg-red', 32: 'fg-green', 33: 'fg-yellow',
  34: 'fg-blue', 35: 'fg-magenta', 36: 'fg-cyan', 37: 'fg-white'
  40: 'bg-black', 41: 'bg-red', 42: 'bg-green', 43: 'bg-yellow',
  44: 'bg-blue', 45: 'bg-magenta', 46: 'bg-cyan', 47: 'bg-white'

html = (input) ->
  result = input.map (v) ->
    if typeof v == 'string'
      return v
    else if v.cmd == 'm'
      cls = v.args.split(';').map((v) -> COLORS[parseInt v]).join(' ')
      return ''
    else
      return ''
  return result.join(' ')


runner = module.exports =
    build: ->
        runNextJob()

runNextJob = ->
    return no if jobs.current?
    jobs.next ->
        git.pull ->
            runTask (success)->
                jobs.currentComplete success, ->
                    runNextJob()

runTask = (next)->
    logQ = []
    logQ.push ["Executing '#{git.runner}'\n\n", false]
    logQ.push ["Running build task: #{git.runner}\n\n", false]

    j = spawn "/bin/bash", [git.runner]
    j.stdout.on 'data', (data) =>
      logQ.push [data, false]
    j.stderr.on 'data', (data) =>
      logQ.push [data, true]
    j.on 'error', (err) =>
      logQ.push([
        "Caught error running task #{err.message}\n\n",
        true,
        -> runFile git.failure, next, yes
      ])
    j.on 'close', (code) =>
      if code == 0
        logQ.push([
          "Process exitied with code #{code}\n\n",
          false,
          -> runFile git.success, next, yes
        ])
      else
        logQ.push([
          "Process exited with code #{code}\n\n",
          true,
          -> runFile git.failure, next, no
        ])

    # to maintain log order: every second, check if we have anything in the
    # log queue, and if we do, push and call log check again. If we find an
    # item in the queue with 3 arguments, it is passing a done callback, so
    # will be the last thing we will need to process. In this case, cancel
    # the timer.
    interval = null
    processLogQ = ->
      clearInterval interval if interval
      if logQ.length is 0
        interval = setInterval(processLogQ, 1000)
        return
      args = logQ.shift()
      if args.length is 3
        updateLog.apply this, args
      else
        updateLog.apply this, args.concat(->
          processLogQ()
        )
    interval = setInterval(processLogQ, 1000)

runFile = (file, next, args=null) ->
    jobs.updateLog jobs.current, "Executing #{file}", ->
        console.log "Executing #{file}".grey
        exec file, (error, stdout, stderr)=>
            if error?
                updateLog error, true, ->
                    updateLog stdout, true, ->
                        updateLog stderr, true, ->
                            next(args)
            else
                updateLog stdout, true, ->
                    next(args)

updateLog = (buffer, isError, done) ->
    content = html tokenize buffer.toString()
    if isError
        errorClass = ' error'
        console.log "#{content}".red
    else
        errorClass = ''
        console.log content
    jobs.updateLog jobs.current, content, done
