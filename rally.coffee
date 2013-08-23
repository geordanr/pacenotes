https = require 'https'

Number::toRad = () ->
    this * (Math.PI / 180)

Number::toDeg = () ->
    this * (180 / Math.PI)

class Point
    constructor: (latitude_deg, longitude_deg) ->
        @lat_deg = latitude_deg
        @long_deg = longitude_deg
        @lat_rad = latitude_deg.toRad()
        @long_rad = longitude_deg.toRad()

    toString: () ->
        "<Point latitude=#{@lat_deg}, longitude=#{@long_deg}>"

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
                points = decodePolyline(step.polyline.points)
                console.log points

decodePolyline = (encoded) ->
    # returns list of
    #   point: ...
    #   distance: ...
    #   bearing: ...
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
    # initial lat/long
    output_list = [
        point: new Point(values.shift(), values.shift())
        distance: 0
        bearing: null
    ]
    while values.length > 0
        prev_point = output_list[output_list.length - 1].point
        next_point = new Point(prev_point.lat_deg + values.shift(), prev_point.long_deg + values.shift())
        distBearing_data = distanceAndBearing prev_point, next_point
        output_list.push
            point: next_point
            distance: distBearing_data.distance
            bearing: distBearing_data.bearing
    output_list

distanceAndBearing = (source_point, dest_point) ->
    # from http://www.movable-type.co.uk/scripts/latlong.html
    # return distance in meters, bearing in radians
    lat1 = source_point.lat_rad
    lat2 = dest_point.lat_rad
    lon1 = source_point.long_rad
    lon2 = dest_point.long_rad

    R = 6371000 # Earth's radius in meters
    dLat = lat2 - lat1
    dLon = lon2 - lon1

    a = Math.sin(dLat/2) * Math.sin(dLat/2) +
        Math.sin(dLon/2) * Math.sin(dLon/2) * Math.cos(lat1) * Math.cos(lat2)
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    dist = R * c

    y = Math.sin(dLon) * Math.cos(lat2)
    x = Math.cos(lat1)*Math.sin(lat2) - Math.sin(lat1)*Math.cos(lat2)*Math.cos(dLon)
    brng = Math.atan2(y, x)

    data =
        distance: dist
        bearing: brng

    return data

getDirectionPolylines '1 Infinite Loop Cupertino, CA 95014', '1600 Amphitheatre Parkway Mountain View, CA 94043'
