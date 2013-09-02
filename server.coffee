express = require 'express'
#engines = require 'consolidate'
#require 'hamljs-coffee'

pacenotes = require './lib/pacenotes'

app = express()

app.configure () ->
#    app.engine 'haml', engines.haml
    app.set 'view engine', 'jade'

app.use express.static(__dirname + '/public')

app.use (req, res, next) ->
    res.locals.origin = req.query.origin ? null
    res.locals.destination = req.query.destination ? null
    next()

app.get '/', (req, res) ->
    if 'origin' of req.query and 'destination' of req.query
        res.locals.origin = req.query.origin
        res.locals.destination = req.query.destination
        pacenotes.paceNotes req.query.origin, req.query.destination, (data) ->
            res.locals.leg = data.leg
            res.locals.error = data.error
            res.render 'index'
    else
        res.locals.origin = ''
        res.locals.destination = ''
        res.render 'index'

app.listen 3000
console.log "Listening..."
