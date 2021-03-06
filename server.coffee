express = require 'express'
pacenotes = require './lib/pacenotes'

app = express()

app.configure () ->
    app.set 'view engine', 'jade'

app.configure 'development', () ->
    app.set 'port', 3000

app.configure 'production', () ->
    app.set 'port', process.env.PORT ? 80

app.use (req, res, next) ->
    console.log "#{new Date().toUTCString()} #{req.ip} #{req.method} #{req.path}"
    next()

app.use express.compress()

app.use express.static(__dirname + '/public')

app.use (req, res, next) ->
    res.locals.origin = req.query.origin ? null
    res.locals.destination = req.query.destination ? null
    next()

app.get '/', (req, res) ->
    if 'origin' of req.query and 'destination' of req.query
        res.locals.origin = req.query.origin
        res.locals.destination = req.query.destination
        try
            pacenotes.paceNotes req.query.origin, req.query.destination, (result) ->
                res.locals.leg = result.data
                res.locals.error = result.error
                res.render 'index'
        catch err
            res.locals.leg = null
            res.locals.error = err
            res.render 'index'
    else
        res.locals.origin = ''
        res.locals.destination = ''
        res.render 'index'

app.listen app.get('port')
console.log "Listening on port #{app.get 'port'}..."
