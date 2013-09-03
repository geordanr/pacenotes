https = require 'https'

IM_ON_A_PLANE = false

# XXX DEBUG
fs = require 'fs'

Number::toRad = () ->
    this * (Math.PI / 180)

Number::toDeg = () ->
    ((this * (180 / Math.PI)) + 360) % 360

Number::toBearing = () ->
    if this > 180
        this - 360
    else if this < -180
        this + 360
    else
        this

Number::toDirection = () ->
    if Math.abs(this) < TURN_THRESHOLD_DEG
        'STRAIGHT'
    else if this < 0
        'LEFT'
    else
        'RIGHT'

Array::max = () ->
  Math.max.apply null, this

Array::min = () ->
  Math.min.apply null, this


DISTANCE_THRESHOLD = 5
TURN_THRESHOLD_DEG = 10
MIN_STRAIGHT_LENGTH = 50
MIN_HILL_ELEVATION = 2

DIRECTION_TO_ICON_CLASS=
    STRAIGHT: 'icon-arrow-up'
    LEFT: 'icon-mail-reply'
    RIGHT: 'icon-mail-forward'

exports.paceNotes = (origin, destination, callback=displaySteps) ->
    # The main thing.
    if IM_ON_A_PLANE
        fs.readFile 'directions.json', (err, data) ->
            parseMapData JSON.parse(data), callback
    else
        https.get "https://maps.googleapis.com/maps/api/directions/json?sensor=false&origin=#{origin}&destination=#{destination}", (res) ->
            json = ''
            res.on 'data', (chunk) ->
                json += chunk
            res.on 'end', () ->
                try
                    parseMapData JSON.parse(json), callback
                catch err
                    callback
                        data: null
                        error: err
        .on 'error', (e) ->
            callback
                data: null
                error: "Error contacting Google Maps API: #{e.message}"
    null

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
        "[Point latitude=#{@lat_deg.toFixed 5}, longitude=#{@long_deg.toFixed 5}, elevation=#{@elevation.toFixed 5}]"

class Segment
    constructor: (src_point, dest_point) ->
        @src_point = src_point
        @dest_point = dest_point
        @climb = dest_point.elevation - src_point.elevation

        @start_elevation = src_point.elevation
        @end_elevation = dest_point.elevation

        # This can be updated later during straight collapse
        @min_elevation = Math.min(src_point.elevation, dest_point.elevation)
        @max_elevation = Math.max(src_point.elevation, dest_point.elevation)

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
        @bearing = Math.atan2(y, x).toDeg().toBearing()

    toString: () ->
        "[Segment from=#{@src_point.lat_deg.toFixed 5},#{@src_point.long_deg.toFixed 5},#{@src_point.elevation.toFixed 2} to=#{@dest_point.lat_deg.toFixed 5},#{@dest_point.long_deg.toFixed 5},#{@dest_point.elevation.toFixed 2} distance=#{@distance.toFixed 2} bearing=#{@bearing.toFixed 2} climb=#{@climb.toFixed 2} start_elev=#{@start_elevation.toFixed 2} min_elev=#{@min_elevation.toFixed 2} max_elev=#{@max_elevation.toFixed 2} end_elev=#{@end_elevation.toFixed 2}]"

class Curve
    # direction LEFT/RIGHT/STRAIGHT
    # tightness 1-6
    # climb UPHILL/DOWNHILL/CREST
    constructor: (direction, segments) ->
        @segments = segments
        @direction = direction

        if @segments.length == 1 and @direction != 'STRAIGHT'
            throw "Single segment curves must be straights, got direction #{@direction} for segments: #{@segments}"

        # analyze curve
        @distance = 0
        start_elevation = segments[0].start_elevation
        end_elevation = segments[segments.length-1].end_elevation
        min_elevation = Infinity
        max_elevation = -Infinity
        total_bearing_delta = 0
        prev_bearing = segments[0].bearing

        for segment in segments
            @distance += segment.distance
            min_elevations = segment.min_elevation if segment.min_elevation < min_elevation
            max_elevations = segment.max_elevation if segment.max_elevation < max_elevation
            total_bearing_delta += (segment.bearing - prev_bearing).toBearing()
            prev_bearing = segment.bearing
            #console.log "segment bearing #{segment.bearing}"
        #console.log "=== total bearing delta #{total_bearing_delta}"

        climb_attributes = []
        if Math.abs(start_elevation - end_elevation) > MIN_HILL_ELEVATION
            climb_attributes.push(if start_elevation < end_elevation then 'UPHILL' else 'DOWNHILL')
        if max_elevation > start_elevation or max_elevation > end_elevation
            climb_attributes.push 'CREST'
        if min_elevation < start_elevation or min_elevation < end_elevation
            climb_attributes.push 'DIP'
        @climb = climb_attributes.join ' '

        @rounded_distance = 5 * parseInt(@distance / 5)

        #console.log "final bearing delta #{total_bearing_delta} (direction #{@direction}) over #{@segments.length} segments"
        @debug_info = ''
        @tightness = ''
        @turn_type = ''
        @turn_delta = ''

        @turn_info = ''
        unless @direction == 'STRAIGHT'
            total_turn = Math.abs(total_bearing_delta)
            deg_per_m = total_turn / @distance
            @tightness = if deg_per_m < 0.3
                    6
                else if deg_per_m < 0.4
                    5
                else if deg_per_m < 0.5
                    4
                else if deg_per_m < 0.6
                    3
                else if deg_per_m < 0.7
                    2
                else
                    1

            @turn_type = if total_turn > 135
                    'HAIRPIN'
                else if total_turn > 90
                    'LONG'
                else
                    ''

            bdiff = ((s.bearing - segments[i-1].bearing).toBearing() for s, i in segments when i > 0)
            dbdiff_dt = (b - bdiff[i-1] for b, i in bdiff when i > 0)
            total_diff = 0
            for d in dbdiff_dt
                total_diff += d
            @turn_delta = if total_diff < -5
                    'TIGHTENS'
                else if total_diff > 5
                    'OPENS'
                else ''

            @turn_info = [ @tightness, @turn_type, @turn_delta ].join ' '

            @debug_info += " (#{deg_per_m.toFixed 2} deg/m, total turn #{total_turn.toFixed 2} deg), total bearing diff #{total_diff.toFixed 2}"
            @debug_info = ''

    toString: () ->
        #curve_breakdown = "\n" + ( "\t#{segment.toString()}" for segment in @segments ).join '\n'
        """#{@direction} #{@turn_info} #{@climb} #{@rounded_distance}m #{@debug_info}""".replace(/\s+/g, ' ')

    toHTML: () ->
        """#{@direction} <strong>#{@tightness}</strong> #{@turn_type} #{@turn_delta} #{@climb} #{@rounded_distance}m #{@debug_info}"""

    directionIconHTML: () ->
        """<i class="#{DIRECTION_TO_ICON_CLASS[@direction]} icon-large"></i>"""

class Step
    # A gmaps "step"
    constructor: (step_idx, instructions, curves) ->
        @step_idx = step_idx
        @instructions = instructions
        @curves = curves

    toString: () ->
        "[Step ##{@step_idx+1}: #{@instructions}]"

class Leg
    # A gmaps "leg"
    constructor: (leg_idx, start, end, steps) ->
        @leg_idx = leg_idx
        @start = start
        @end = end
        @steps = steps

    toString: () ->
        """#{@start} to #{@end}"""

    toHTML: () ->
        """<strong>#{@start}</strong> to <strong>#{@end}</strong>"""

generateCurvesForStep = (step_idx, instructions, segments, callback) ->
    # Returns list of Curves
    errors = null
    curves = null
    try

        segments = collapseStraights segments
        if segments.length == 1
            #console.log "shortcut straight"
            curves = [ new Curve('STRAIGHT', segments) ]
        else
            prev_seg = null
            for segment in segments
                bearing_delta = if prev_seg? then (segment.bearing - prev_seg.bearing).toBearing() else 0
                prev_seg = segment
                #console.log "Step #{step_idx}: #{segment.toString()}, bearing delta #{bearing_delta.toFixed 2}"

            curves = []
            current_curve_segments = []
            possible_next_straight_segments = []

            current_curve_direction = null
            total_curve_length = 0

            for segment in segments
                prev_segment = current_curve_segments[current_curve_segments.length-1]
                if current_curve_segments.length < 2 and current_curve_direction is null
                    # haven't collected enough to know what's going on
                    current_curve_segments.push segment
                    total_curve_length += segment.distance
                    if current_curve_segments.length == 2
                        # we have enough to set the direction
                        current_curve_direction = (segment.bearing - prev_segment.bearing).toBearing().toDirection()
                        #console.log "initial direction #{current_curve_direction} based on bearing change #{(segment.bearing - prev_segment.bearing).toBearing()}, heading #{segment.bearing.toFixed 2}"
                else
                    # if the segment is long enough to constitute a straight on its own and we're not going straight already, output current curve and begin a new straight
                    if current_curve_direction != 'STRAIGHT' and segment.distance > MIN_STRAIGHT_LENGTH
                        curves.push new Curve(current_curve_direction, current_curve_segments)
                        current_curve_segments = [ ]
                        current_curve_direction = 'STRAIGHT'
                    else
                        # see if this segment is valid for extending the current curve
                        bearing_delta = (segment.bearing - prev_segment.bearing).toBearing()
                        new_direction = bearing_delta.toDirection()
                        #console.log "was heading #{prev_segment.bearing.toFixed 2}, now heading #{segment.bearing.toFixed 2}; bearing delta is now #{bearing_delta.toFixed 2}, setting new direction to #{new_direction}"

                        if new_direction != current_curve_direction
                            # output the current curve, but hang on to the last segment of that curve
                            #console.log "direction changed from #{current_curve_direction} to #{new_direction}, pushing curve with direction #{current_curve_direction}"
                            curves.push new Curve(current_curve_direction, current_curve_segments)
                            current_curve_segments = [ prev_segment ]
                            current_curve_direction = new_direction

                    # either way, add the segment
                    current_curve_segments.push segment
            if current_curve_segments.length > 0
                #console.log "leftover segments forming a curve with direction #{current_curve_direction}"
                curves.push new Curve(current_curve_direction, current_curve_segments)
    catch err
        errors = err
    finally
        callback
            data: curves
            error: null

collapseStraights = (segments) ->
    # collapses strings of segments whose total bearing delta is < TURN_THRESHOLD_DEG

    debug_id = parseInt(Math.random() * 1000)
    #console.log "#{debug_id}: all segments:\n#{("\t#{segment.toString()}" for segment in segments).join "\n"}"

    collapsed_segments = []
    possible_straight_segments = []
    total_bearing_delta = null
    for segment in segments
        #console.log "#{debug_id}: examining segment #{segment.toString()}"
        if possible_straight_segments.length == 0
            possible_straight_segments.push segment
            total_bearing_delta = 0
        else
            prev_straight_segment = possible_straight_segments[possible_straight_segments.length-1]
            bearing_delta = (segment.bearing - prev_straight_segment.bearing).toBearing()
            if bearing_delta.toDirection() == 'STRAIGHT'
                # check if this makes the total bearing change too high
                if (total_bearing_delta + bearing_delta).toBearing().toDirection() == 'STRAIGHT'
                    # extends the straight
                    possible_straight_segments.push segment
                    total_bearing_delta = (total_bearing_delta + bearing_delta).toBearing()
                    #console.log "#{debug_id}: current segment extends the straight, possible straight segments is now:"
                    #for s in possible_straight_segments
                    #    console.log "#{debug_id}:\t#{s.toString()}"
                    continue
            # a new straight or a curve is starting
            #console.log "#{debug_id}: creating collapsed segment from possible straight:"
            #for s in possible_straight_segments
            #    console.log "#{debug_id}:\t#{s.toString()}"
            new_segment = new Segment(possible_straight_segments[0].src_point, prev_straight_segment.dest_point)
            min_elevations = (s.min_elevation for s in possible_straight_segments)
            max_elevations = (s.max_elevation for s in possible_straight_segments)
            elevations = min_elevations.concat max_elevations
            new_segment.min_elevation = elevations.min()
            new_segment.max_elevation = elevations.max()
            collapsed_segments.push new_segment
            possible_straight_segments = [ segment ]
            #console.log "#{debug_id}: possible straight segment list is now:"
            #for s in possible_straight_segments
            #    console.log "#{debug_id}:\t#{s.toString()}"
            total_bearing_delta = 0
    if possible_straight_segments.length > 0
        #console.log "#{debug_id}: creating straight from leftover possible straight:"
        #for s in possible_straight_segments
        #    console.log "#{debug_id}:\t#{s.toString()}"
        collapsed_segments.push new Segment(possible_straight_segments[0].src_point, possible_straight_segments[possible_straight_segments.length-1].dest_point)

    collapsed_segments

parseMapData = (mapData_obj, callback) ->
    # Parse map directions object
    # Calls callback with steps
    throw "Could not get directions, status was: #{mapData_obj.status}" unless mapData_obj.status == 'OK'
    steps = []
    # Take first route for now
    route = mapData_obj.routes[0]
    for leg, leg_idx in route.legs
        for step, step_idx in leg.steps
            #continue unless step_idx == 2 # DEBUG
            steps.push null
            polyline = step.polyline.points
            instructions = step.html_instructions
            do (polyline, instructions, step_idx, steps) ->
                getSegments polyline, (result) ->
                    #console.log "getSegments: #{result}"
                    segments = if result.error then [] else result.data
                    generateCurvesForStep step_idx, instructions, segments, (result) ->
                        #console.log "generateCurvesForStep: #{result}"
                        curves = if result.error then [] else result.data
                        steps[step_idx] = new Step(step_idx, instructions, curves)
                        if (s for s in steps when s is null).length == 0
                            # done waiting for elevation callbacks
                            callback
                                data: new Leg(leg_idx, leg.start_address, leg.end_address, steps)
                                error: null

displaySteps = (leg) ->
    console.log leg.toString()
    for step in leg.steps
        console.log step.toString()
        for curve in step.curves
            console.log "  #{curve.toString()}"

getElevationsAlongPolyline = (polyline, callback) ->
    # Calls callback with elevation_data.results
    if IM_ON_A_PLANE
        fs.readFile "elevations.json", (err, data) ->
            parseElevationData JSON.parse(data)[polyline], callback
    else
        https.get "https://maps.googleapis.com/maps/api/elevation/json?sensor=false&locations=enc:#{polyline}", (res) ->
            json = ''
            if res.statusCode == 200
                res.on 'data', (chunk) ->
                    json += chunk
                res.on 'end', () ->
                    try
                        parseElevationData JSON.parse(json), callback
                    catch err
                        console.log "Error parsing JSON from https://maps.googleapis.com/maps/api/elevation/json?sensor=false&locations=enc:#{polyline} - error was #{err}"
                        callback
                            data: null
                            error: err
            else
                switch res.statusCode
                    when 413
                        callback
                            data: null
                            error: "URL is too long to fetch"
                    when 414
                        callback
                            data: null
                            error: "Step is too long to fetch elevations"
                    else
                        callback
                            data: null
                            error: "Unknown status #{res.statusCode}"
        .on 'error', (e) ->
            console.log "Error: #{e.message}"

parseElevationData = (elevData_obj, callback) ->
    throw "Could not get elevation data, status was: #{elevData_obj.status}" unless elevData_obj.status == 'OK'
    callback
        data: elevData_obj.results
        error: null

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
    getElevationsAlongPolyline polyline, (result) ->
        elevation_data = if result.error then null else result.data
        segments = []
        errors = null
        try
            decoded_polyline = decodePolyline polyline
            i = 0

            # initial point
            prev_point = new Point(decoded_polyline.shift(), decoded_polyline.shift(), elevation_data?[i].elevation ? 0)

            i++
            while decoded_polyline.length > 0
                new_point = new Point(decoded_polyline.shift(), decoded_polyline.shift(), elevation_data?[i].elevation ? 0)
                i++
                new_segment = new Segment(prev_point, new_point)
                if new_segment.distance > DISTANCE_THRESHOLD
                    segments.push new_segment
                    prev_point = new_point
        catch err
            errors = err
        finally
            callback
                data: segments
                error: errors

test_decodePolyline = () ->
    results = decodePolyline('''_p~iF~ps|U_ulLnnqC_mqNvxq`@''')
    if "#{[ 38.5, -120.2, 40.7, -120.95, 43.252, -126.453 ]}" != "#{results}"
        throw "decodePolyline() failed (results were: #{results})"
    else
        console.log 'decodePolyline() ok'

#exports.paceNotes '1 Infinite Loop Cupertino, CA 95014', '1600 Amphitheatre Parkway Mountain View, CA 94043'
#exports.paceNotes '1308 Old Bayshore Hwy, Burlingame, CA 94010', '1040 Broadway, Burlingame, CA, 94010'
#exports.paceNotes '17288 Skyline Blvd, Woodside, CA 94062', '2 Friars Ln, Woodside, CA 94062'
