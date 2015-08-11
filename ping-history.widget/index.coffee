###  PING HISTORY WIDGET  ###
# Customization:
#   enter domains to ping and aliases to display (lines 15-16)
#   and adjust position on desktop (lines 132-133)

# this is the shell command that gets executed every time this widget refreshes
command: """
  # command pings domains in array 'domains'
  # and displays result like 'name:last string of ping output', e.g.:
  #  domain1_name:round-trip min/avg/max/stddev = 3.439/3.439/3.439/0.000 ms
  #  domain2_name:1 packets transmitted, 0 packets received, 100.0% packet loss
  #  domain3_name:ping: cannot resolve domain4_name: Unknown host
  
  ###  LIST YOUR DOMAINS HERE
  declare -a domains=( 8.8.8.8  ya.ru   bbc.co.uk )
  declare -a aliases=( dns      yandex  bbc       )
  ###  AND DON'T FORGET SHORT ALIASES

  for i in "${!domains[@]}"; do
  	echo -n "${aliases[$i]}:"
  	echo $(ping -o -c 1 -t 1 ${domains[$i]} | tail -n 1)
  done
  """

# regexp to get alias and ping data from bash output
regexp: /^([^:]+):(.+=\s([^/]+)|.+)?/

# the refresh frequency in milliseconds
# better keep value in seconds higher than domains count (3 domains => 3000+)
# or you'll be getting "error running command" sometimes
refreshFrequency: 7000

settings:
  canvas_w: 90 # width and
  canvas_h: 15 # height of canvas for each graph in px
  default_max_ms: 50 # graph scale when ping is low
  bar_width: 2 # width in px of single bar on graph
  bar_gap:   1 # gap in px between bars
  graph_direction: 'ltr' # which way fill the graph - 'ltr' or 'rtl'

bars_colors: [
  {min: -1, max: 0,    color: 'rgba(0,0,0,.6)'} # unavailable
  {min: 0,  max: 5,    color: '#74fc55'}
  {min: 5,  max: 10,   color: '#ffed54'}
  {min: 10, max: 20,   color: '#ffc154'}
  {min: 20, max: 50,   color: '#ff9754'}
  {min: 50, max: 9999, color: '#ff6254'}
]

# create table
render: (output) -> """
  <table>
    #{(for o in output.split '\n' when o and @regexp.test o
      @_create_row o
    ).join ''}
  </table>
  """

# init inner values
afterRender: (domEl) ->
  obj = this
  $(domEl).find('tr').each ->
    el = $(this)
    name = el.data 'name'
    obj.pings[name] = 0
    obj.maximums[name] = 0
    obj.history[name] = []
    obj.contexts[name] = el.find('canvas')[0].getContext '2d'

# display actual info
update: (output, domEl) ->
  for o in output.split '\n' when o and @regexp.test o
    [s, name, r, ping] = o.match @regexp
    @_recalc_values name, ping ? 0
    @_update_row name, $(domEl).find "[data-name='#{name}']"


# creates single row in the table on first load
_create_row: (output) ->
  name = output.split(':')[0]
  """
  <tr data-name="#{name}">
    <td class="name">#{name}</td>
    <td class="ping"></td>
    <td class="graph">
      <canvas width="#{@settings.canvas_w}" height="#{@settings.canvas_h}"></canvas>
    </td>
    <td class="max">10</td>
  </tr>
  """

# recalculates inner values on update
_recalc_values: (name, ping) ->
  @pings[name] = if ping? then Math.round(ping*10) / 10 else 0
  @history[name].unshift @pings[name]
  if @history[name].length > Math.ceil @settings.canvas_w / (@settings.bar_width + @settings.bar_gap)
    do @history[name].pop
  @maximums[name] = Math.max.apply null, @history[name]
  @maximums[name] = switch
    when @maximums[name] <= @settings.default_max_ms
      @settings.default_max_ms
    when @settings.default_max_ms < @maximums[name] <= 50
      Math.ceil(@maximums[name] / 10) * 10
    when 50 < @maximums[name] <= 500
      Math.ceil(@maximums[name] / 100) * 100
    else
      Math.ceil(@maximums[name] / 1000) * 1000

# updates current ping and redraws graph
_update_row: (name, el) ->
  el.find('.max').html @maximums[name]
  if @pings[name]
    el.removeClass 'down' if el.hasClass 'down'
    el.find('.ping').html @pings[name].toFixed(1)
  else
    el.addClass 'down' unless el.hasClass 'down'
    el.find('.ping').html ''
  
  # clearing all graph area, for it's being redrawn completely at each cycle
  @contexts[name].clearRect 0, 0, @settings.canvas_w, @settings.canvas_h
  
  # for how many pixels graph area moves after drawing each separate bar
  step = @settings.bar_width + @settings.bar_gap
  
  do @contexts[name].beginPath
  # iterate over each value in history and draw a bar
  for p in @history[name]
    # choose color for the bar
    for g in @bars_colors when g.min < p <= g.max
      @contexts[name].fillStyle = g.color
    
    # ################################################ #
    if @settings.graph_direction is 'ltr'
      # LEFT-TO-RIGHT
      # draw the bar itself
      #  fillRect x, y, w, h
      #  x = 0 - drawing from left edge
      #  y = 0 when no ping, draw fullheight black bar
      #  y = canvas_height - part ping takes in max value, so
      #    starting to draw rectangle not from top of the canvas, but lower
      #  w = bar_width
      #  h = canvas_height - doesn't matter if it goes below the bottom edge
      @contexts[name].fillRect 0
      , (if p is 0 then 0 else @settings.canvas_h - (p * @settings.canvas_h / @maximums[name]))
      , @settings.bar_width
      , @settings.canvas_h
      # move all graph area for 'step' pixels right
      #  transform a, b, c, d, e, f
      #  e - Moves the the drawing horizontally
      #  http://www.w3schools.com/tags/canvas_transform.asp
      @contexts[name].transform 1, 0, 0, 1, step, 0
    else
      # RIGHT-TO-LEFT
      # draw the bar itself
      @contexts[name].fillRect @settings.canvas_w - @settings.bar_width
      , (if p is 0 then 0 else @settings.canvas_h - (p * @settings.canvas_h / @maximums[name]))
      , @settings.bar_width
      , @settings.canvas_h
      # move all graph area for 'step' pixels left
      @contexts[name].transform 1, 0, 0, 1, -step, 0
    # ################################################ #
  
  # move canvas back, or else every cycle bars will be appended, not redrawn
  if @settings.graph_direction is 'ltr'
    # LEFT-TO-RIGHT
    @contexts[name].transform 1, 0, 0, 1, (-step * @history[name].length), 0
  else
    # RIGHT-TO-LEFT
    @contexts[name].transform 1, 0, 0, 1, (step * @history[name].length), 0



# the CSS style for this widget, written using Stylus
# (http://learnboost.github.io/stylus/)
style: """
  // SET DESIRED POSITION AND FONT COLOR
  top 10px
  left 10px
  color white
  
  box-sizing border-box
      
  canvas
    background rgba(#000, 0.2)
  
  table
    border-collapse collapse
    border-spacing 0
    
    // emphasize unavailable domain with colored background
    tr.down > td
      background-color rgba(#F00, 0.7)
    
    td
      vertical-align top
      padding 1px 3px 0
      font-family Helvetica Neue
      font-size 11px
      line-height 10px
    
    td.name
      font-family Monaco
      padding-top 5px
      padding-right 8px
    
    td.ping
      font-weight 200
      font-size 15px
      text-align right
      padding-top 3px
      min-width 50px
    
    td.max
      font-size 8px
      line-height 8px
      padding-left 0
"""

contexts: {} # canvases' contexts
pings:    {} # last pings values
history:  {} # pings historical values
maximums: {} # max ping values in saved history
