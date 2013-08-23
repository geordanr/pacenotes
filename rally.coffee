https = require 'https'

getDirectionPolylines = (origin, destination) ->
    options =
    https.get "https://maps.googleapis.com/maps/api/directions/json?sensor=false&origin=#{origin}&destination=#{destination}", (res) ->
        json = ''
        res.on 'data', (chunk) ->
            json += chunk
        res.on 'end', () ->
            parseMapData JSON.parse(json)
    .on 'error', (e) ->
        console.log "Error: #{e.message}"

parseMapData = (mapData_obj) ->
    for route in mapData_obj.routes
        for leg in route.legs
            for step in leg.steps
                console.log decodePolyline(step.polyline.points)

decodePolyline = (encoded) ->
    values = []
    chunks = []
    for c, i in encoded
        chunk = encoded.charCodeAt(i) - 63
        chunks.push (chunk & 31)
        if (chunk & 0x20) == 0
            # last chunk
            val = 0
            for chunk in chunks.reverse()
                val = (val << 5) | chunk
            val = if ((val & 1) == 1) then ~(val >> 1) else (val >> 1)
            values.push (val / 1e5)
            val = 0
            chunks = []
    values

getDirectionPolylines '1 Infinite Loop Cupertino, CA 95014', '1600 Amphitheatre Parkway Mountain View, CA 94043'
