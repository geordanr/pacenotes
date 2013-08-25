https = require 'https'
iced = require('iced-coffee-script').iced

Number::toRad = () ->
    this * (Math.PI / 180)

Number::toDeg = () ->
    ((this * (180 / Math.PI)) + 360) % 360

class Point
    constructor: (latitude_deg, longitude_deg, elevation) ->
        @lat_deg = latitude_deg
        @long_deg = longitude_deg
        @lat_rad = latitude_deg.toRad()
        @long_rad = longitude_deg.toRad()
        @elevation = elevation

    setElevation: (elevation) ->
        @elevation = elevation

    toString: () ->
        "<Point latitude=#{@lat_deg.toFixed 5}, longitude=#{@long_deg.toFixed 5}, elevation=#{@elevation.toFixed 5}>"

class Segment
    constructor: (src_point, dest_point) ->
        @src_point = src_point
        @dest_point = dest_point
        @climb = dest_point.elevation - src_point.elevation

        @setDistanceAndBearing()

    setDistanceAndBearing: () ->
        # from http://www.movable-type.co.uk/scripts/latlong.html
        # return distance in meters, bearing in radians
        lat1 = @src_point.lat_rad
        lat2 = @dest_point.lat_rad
        lon1 = @src_point.long_rad
        lon2 = @dest_point.long_rad

        R = 6371000 # Earth's radius in meters
        dLat = lat2 - lat1
        dLon = lon2 - lon1

        a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.sin(dLon/2) * Math.sin(dLon/2) * Math.cos(lat1) * Math.cos(lat2)
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
        @distance = R * c

        y = Math.sin(dLon) * Math.cos(lat2)
        x = Math.cos(lat1)*Math.sin(lat2) - Math.sin(lat1)*Math.cos(lat2)*Math.cos(dLon)
        @bearing = Math.atan2(y, x).toDeg()

    toString: () ->
        "<Segment from=#{@src_point.lat_deg.toFixed 5},#{@src_point.long_deg.toFixed 5},#{@src_point.elevation.toFixed 2} to=#{@dest_point.lat_deg.toFixed 5},#{@dest_point.long_deg.toFixed 5},#{@dest_point.elevation.toFixed 2} distance=#{@distance.toFixed 2} bearing=#{@bearing.toFixed 2} climb=#{@climb.toFixed 2}>"

computePaceNotes = (origin, destination) ->
    # The main thing.
    https.get "https://maps.googleapis.com/maps/api/directions/json?sensor=false&origin=#{origin}&destination=#{destination}", (res) ->
        json = ''
        res.on 'data', (chunk) ->
            json += chunk
        res.on 'end', () ->
            parseMapData JSON.parse(json)
    .on 'error', (e) ->
        console.log "Error: #{e.message}"

parseMapData = (mapData_obj) ->
    # Parse map directions object
    throw "Could not get directions, status was: #{mapData_obj.status}" unless mapData_obj.status == 'OK'
    for route in mapData_obj.routes
        for leg in route.legs
            for step, step_idx in leg.steps
                continue unless step_idx == 0
                polyline = step.polyline.points
                instructions = step.html_instructions
                do (polyline, instructions) ->
                    getSegments polyline, (segment_data) ->
                        console.log "--- #{instructions}"
                        for segment in segment_data
                            console.log segment.toString()

getElevationsAlongPolyline = (polyline, callback) ->
    # Calls callback with elevation_data.results
    https.get "https://maps.googleapis.com/maps/api/elevation/json?sensor=false&locations=enc:#{polyline}", (res) ->
        json = ''
        res.on 'data', (chunk) ->
            json += chunk
        res.on 'end', () ->
            parseElevationData JSON.parse(json), callback
    .on 'error', (e) ->
        console.log "Error: #{e.message}"

parseElevationData = (elevData_obj, callback) ->
    throw "Could not get elevation data, status was: #{elevData_obj.status}" unless elevData_obj.status == 'OK'
    callback elevData_obj.results

decodePolyline = (encoded) ->
    # returns decoded values (with diffs applied)
    values = []
    chunks = []
    lat = 0
    long = 0
    for c, i in encoded
        chunk = encoded.charCodeAt(i) - 63
        chunks.push (chunk & 31)
        if (chunk & 0x20) == 0
            # last chunk
            val = 0
            for chunk in chunks.reverse()
                val = (val << 5) | chunk
            val = if ((val & 1) == 1) then ~(val >> 1) else (val >> 1)
            val /= 1e5
            if values.length % 2 == 0
                lat += val
                values.push lat
            else
                long += val
                values.push long
            val = 0
            chunks = []
    values

getSegments = (polyline, callback) ->
    # calls callback with list of Segments
    # get elevation data for this polyline
    getElevationsAlongPolyline polyline, (elevation_data) ->
        decoded_polyline = decodePolyline polyline
        segments = []
        i = 0

        # initial point
        prev_point = new Point(decoded_polyline.shift(), decoded_polyline.shift(), elevation_data[i].elevation)

        i++
        while decoded_polyline.length > 0
            new_point = new Point(decoded_polyline.shift(), decoded_polyline.shift(), elevation_data[i].elevation)
            segments.push new Segment(prev_point, new_point)
            prev_point = new_point
            i++

        callback segments

test_decodePolyline = () ->
    results = decodePolyline('''_p~iF~ps|U_ulLnnqC_mqNvxq`@''')
    if "#{[ 38.5, -120.2, 40.7, -120.95, 43.252, -126.453 ]}" != "#{results}"
        throw "decodePolyline() failed (results were: #{results})"
    else
        console.log 'decodePolyline() ok'

#computePaceNotes '1 Infinite Loop Cupertino, CA 95014', '1600 Amphitheatre Parkway Mountain View, CA 94043'
computePaceNotes '1308 Old Bayshore Hwy, Burlingame, CA 94010', '1040 Broadway, Burlingame, CA, 94010'
