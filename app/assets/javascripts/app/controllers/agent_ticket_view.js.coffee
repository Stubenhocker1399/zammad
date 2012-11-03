$ = jQuery.sub()

class Index extends App.Controller
  events:
    'click [data-type=edit]':      'zoom'
    'click [data-type=settings]':  'settings'
    'click [data-type=viewmode]':  'viewmode'
    'click [data-type=page]':      'page'

  constructor: ->
    super

    # check authentication
    return if !@authenticate()

    @view_mode = localStorage.getItem( "mode:#{@view}" ) || 's'
    @log 'view:', @view, @view_mode

    # set title
    @title ''
    @navupdate '#ticket_view/' + @view

    @meta = {}
    @bulk = {}

    # set new key
    @key = 'ticket_overview_' + @view

    # bind to rebuild view event
    App.Event.bind( 'ticket_overview_rebuild', @fetch, 'page' )

    # render
    @fetch()

  fetch: =>

    # use cache of first page
    cache = App.Store.get( @key )
    if cache
      @overview      = cache.overview
      @tickets_count = cache.tickets_count
      @ticket_list   = cache.ticket_list
      @load(cache)

  load: (data) =>

    # get meta data
    @overview = data.overview
    App.Overview.refresh( @overview, { clear: true } )

    App.Overview.unbind('local:rerender')
    App.Overview.bind 'local:rerender', (record) =>
      @log 'rerender...', record
      @render()

    App.Overview.unbind('local:refetch')
    App.Overview.bind 'local:refetch', (record) =>
      @log 'refetch...', record
      @fetch()

#    # bind render after a change is done
#    App.Collection.observe(
#      level:       'page',
#      collections: [
#        {
#          collection: @genericObject,
#          event:      'refresh change',
#          callback:   @render,
#        },
#      ],
#    )


    @ticket_list_show = []
    for ticket_id in @ticket_list
      @ticket_list_show.push App.Collection.find( 'Ticket', ticket_id )

    # remeber bulk attributes
    @bulk = data.bulk

    # set cache
#    App.Store.write( @key, data )

    # render page
    @render()

  render: ->

    @selected = @bulkGetSelected()

    # set page title
    @title @overview.meta.name

    # get total pages
    pages_total =  parseInt( ( @tickets_count / @overview.view[@view_mode].per_page ) + 0.99999 ) || 1

    # render init page
    edit = true
    if @isRole('Customer')
      checkbox = false
      edit = false
    view_modes = [
      {
        name:  'S'
        type:  's'
        class: 'active' if @view_mode is 's'
      },
      {
        name: 'M'
        type: 'm'
        class: 'active' if @view_mode is 'm'
      }
    ]
    html = App.view('agent_ticket_view')(
      overview:    @overview
      view_modes:  view_modes
      pages_total: pages_total
      start_page:  @start_page
      checkbox:    true
      edit:        edit
    )
    html = $(html)
#    html.find('li').removeClass('active')
#    html.find("[data-id=\"#{@start_page}\"]").parents('li').addClass('active')
    @html html

    # create table/overview
    checkbox = true
    table = ''
    if @view_mode is 'm'
      table = App.view('agent_ticket_view/detail')(
        overview: @overview
        objects:  @ticket_list_show
        checkbox: checkbox
      )
      table = $(table)
      table.delegate('[name="bulk_all"]', 'click', (e) ->
        if $(e.target).attr('checked')
          $(e.target).parents().find('[name="bulk"]').attr('checked', true)
        else
          $(e.target).parents().find('[name="bulk"]').attr('checked', false)
      )
      @el.find('.table-overview').append(table)
    else
      shown_all_attributes = @ticketTableAttributes( App.Overview.find( @overview.id ).view.s.overview )
      groupBy = undefined
      if @overview.group_by
        group_by =
          name: @overview.group_by
          id:   @overview.group_by + '_id'

        # remove group by attribute from show attributes list
        shown_all_attributes = _.filter(
          shown_all_attributes
          (item) =>
            return item if item.name isnt @overview.group_by
            return
        )
      new App.ControllerTable(
        el:                @el.find('.table-overview')
        overview_extended: shown_all_attributes
        model:             App.Ticket
        objects:           @ticket_list_show
        checkbox:          checkbox
        groupBy:           group_by
      )

    @bulkSetSelected( @selected )

    # start user popups
    @userPopups()

    # show frontend times
    @frontendTimeUpdate()

    # start bulk action observ
    @el.find('.bulk-action').append( @bulk_form() )
    if @el.find('.table-overview').find('[name="bulk"]:checked').length isnt 0
        @el.find('.bulk-action').removeClass('hide')

    # show/hide bulk action    
    @el.find('.table-overview').delegate('[name="bulk"], [name="bulk_all"]', 'click', (e) =>
      if @el.find('.table-overview').find('[name="bulk"]:checked').length == 0

        # hide
        @el.find('.bulk-action').addClass('hide')
      else

        # show
        @el.find('.bulk-action').removeClass('hide')
    )

  page: (e) =>
    e.preventDefault()
    id = $(e.target).data('id')
    @start_page = id
    @fetch()

  viewmode: (e) =>
    e.preventDefault()
    @start_page    = 1
    mode = $(e.target).data('mode')
    @view_mode = mode
    localStorage.setItem( "mode:#{@view}", mode )
    @fetch()
    @render()

  bulk_form: =>
    @configure_attributes_ticket = [
      { name: 'ticket_state_id',    display: 'State',    tag: 'select',   multiple: false, null: true, relation: 'TicketState', filter: @bulk, translate: true, nulloption: true, default: '', class: 'span2', item_class: 'keepleft' },
      { name: 'ticket_priority_id', display: 'Priority', tag: 'select',   multiple: false, null: true, relation: 'TicketPriority', filter: @bulk, translate: true, nulloption: true, default: '', class: 'span2', item_class: 'keepleft' },
      { name: 'group_id',           display: 'Group',    tag: 'select',   multiple: false, null: true, relation: 'Group', filter: @bulk, nulloption: true, class: 'span2', item_class: 'keepleft'  },
      { name: 'owner_id',           display: 'Owner',    tag: 'select',   multiple: false, null: true, relation: 'User', filter: @bulk, nulloption: true, class: 'span2', item_class: 'keepleft' },
    ]

    # render init page
    html = $( App.view('agent_ticket_view/bulk')() )
    new App.ControllerForm(
      el: html.find('#form-ticket-bulk'),
      model: {
        configure_attributes: @configure_attributes_ticket,
        className:            'create',
      },
      form_data: @bulk,
    )
#    html.delegate('.bulk-action-form', 'submit', (e) =>
    html.bind('submit', (e) =>
      e.preventDefault()
      @bulk_submit(e)
    )
    return html

  bulkGetSelected: ->
    @ticketIDs = []
    @el.find('.table-overview').find('[name="bulk"]:checked').each( (index, element) =>
      ticket_id = $(element).val()
      @ticketIDs.push ticket_id
    )
    @ticketIDs

  bulkSetSelected: (ticketIDs) ->
    @el.find('.table-overview').find('[name="bulk"]').each( (index, element) =>
      ticket_id = $(element).val()
      for ticket_id_selected in ticketIDs
        if ticket_id_selected is ticket_id
          $(element).attr( 'checked', true )
    )

  bulk_submit: (e) =>
    @bulk_count = @el.find('.table-overview').find('[name="bulk"]:checked').length
    @bulk_count_index = 0
    @el.find('.table-overview').find('[name="bulk"]:checked').each( (index, element) =>
      @log '@bulk_count_index', @bulk_count, @bulk_count_index
      ticket_id = $(element).val()
      ticket = App.Ticket.find(ticket_id)
      params = @formParam(e.target)

      # update ticket
      ticket_update = {}
      for item of params
        if params[item] != ''
          ticket_update[item] = params[item]

#      @log 'update', params, ticket_update, ticket

      ticket.load(ticket_update)
      ticket.save(
        success: (r) =>
          @bulk_count_index++

          # refresh view after all tickets are proceeded
          if @bulk_count_index == @bulk_count

            # rebuild navbar with updated ticket count of overviews
            App.WebSocket.send( event: 'navupdate_ticket_overview' )
            
            # fetch overview data again
            @fetch()
      )
    )

  zoom: (e) =>
    e.preventDefault()
    id = $(e.target).parents('[data-id]').data('id')
    position = $(e.target).parents('[data-position]').data('position')

    # set last overview
    Config['LastOverview']         = @view
    Config['LastOverviewPosition'] = position
    Config['LastOverviewTotal']    = @tickets_count

    @navigate 'ticket/zoom/' + id + '/nav/true'

  settings: (e) =>
    e.preventDefault()
    new Settings(
      overview: App.Overview.find(@overview.id),
      view_mode: @view_mode,
    )

class Settings extends App.ControllerModal
  constructor: ->
    super
    @render()

  render: ->

    @html App.view('dashboard/ticket_settings')(
      overview: @overview,
    )
    @configure_attributes_article = [
#      { name: 'from',                     display: 'From',     tag: 'input',    type: 'text', limit: 100, null: false, class: 'span8',  },
#      { name: 'to',                       display: 'To',          tag: 'input',    type: 'text', limit: 100, null: true, class: 'span7', item_class: 'hide' },
#      { name: 'ticket_article_type_id',   display: 'Type',        tag: 'select',   multiple: false, null: true, relation: 'TicketArticleType', default: '9', class: 'medium', item_class: 'keepleft' },
#      { name: 'internal',                 display: 'Visability',  tag: 'radio',  default: false,  null: true, options: { true: 'internal', false: 'public' }, class: 'medium', item_class: 'keepleft' },
      {
        name:     'per_page'
        display:  'Items per page'
        tag:      'select'
        multiple: false
        null:     false
        default: @overview.view[@view_mode].per_page
        options:
          15: 15
          20: 20
          25: 25
          30: 30
          35: 35
        class: 'medium'
#        item_class: 'keepleft'
      },
      { 
        name:    'attributes'
        display: 'Attributes'
        tag:     'checkbox'
        default: @overview.view[@view_mode].overview
        null:    false
        options:
#          true:  'internal'
#          false: 'public'
          number:                 'Number'
          title:                  'Title'
          customer:               'Customer'
          ticket_state:           'State'
          ticket_priority:        'Priority'
          group:                  'Group'
          owner:                  'Owner'
          created_at:             'Alter'
          last_contact:           'Last Contact'
          last_contact_agent:     'Last Contact Agent'
          last_contact_customer:  'Last Contact Customer'
          first_response:         'First Response'
          close_time:             'Close Time'
        class:      'medium'
      },
      { 
        name:    'order_by'
        display: 'Order'
        tag:     'select'
        default: @overview.order.by
        null:    false
        options:
          number:                 'Number'
          title:                  'Title'
          customer:               'Customer'
          ticket_state:           'State'
          ticket_priority:        'Priority'
          group:                  'Group'
          owner:                  'Owner'
          created_at:             'Alter'
          last_contact:           'Last Contact'
          last_contact_agent:     'Last Contact Agent'
          last_contact_customer:  'Last Contact Customer'
          first_response:         'First Response'
          close_time:             'Close Time'
        class:   'medium'
      },
      { 
        name:    'order_by_direction'
        display: 'Direction'
        tag:     'select'
        default: @overview.order.direction
        null:    false
        options:
          ASC:   'up'
          DESC:  'down'
        class:   'medium'
      },
      { 
        name:    'group_by'
        display: 'Group by'
        tag:     'select'
        default: @overview.group_by
        null:    true
        nulloption: true
        options:
          customer:               'Customer'
          ticket_state:           'State'
          ticket_priority:        'Priority'
          group:                  'Group'
          owner:                  'Owner'
        class:   'medium'
      },
#      {
#        name: 'condition',
#        display: 'Conditions',
#        tag: 'select',
#        multiple: false,
#        null: false,
#        relation: 'TicketArticleType',
#        default: '9',
#        class: 'medium', 
#        item_class: 'keepleft',
#      },
    ]

    new App.ControllerForm(
      el:        @el.find('#form-setting')
      model:     { configure_attributes: @configure_attributes_article }
      autofocus: false
    )

    @modalShow()

  submit: (e) =>
    e.preventDefault()
    params = @formParam(e.target)

    # check if refetch is needed
    @reload_needed = 0
    if @overview.view[@view_mode]['per_page'] isnt params['per_page']
      @overview.view[@view_mode]['per_page'] = params['per_page']
      @reload_needed = 1

    if @overview.order['by'] isnt params['order_by']
      @overview.order['by'] = params['order_by']
      @reload_needed = 1

    if @overview.order['direction'] isnt params['order_by_direction']
      @overview.order['direction'] = params['order_by_direction']
      @reload_needed = 1

    if @overview['group_by'] isnt params['group_by']
      @overview['group_by'] = params['group_by']
      @reload_needed = 1

    @overview.view[@view_mode]['overview'] = params['attributes']

    @overview.save(
      success: =>
        if @reload_needed
          @overview.trigger('local:refetch')
        else
          @overview.trigger('local:rerender')
    )
    @modalHide()

class Router extends App.Controller
  constructor: ->
    super

    # set new key
    @key = 'ticket_overview_' + @view

    # get data
    cache = App.Store.get( @key )
    if cache
      @tickets_count = cache.tickets_count
      @ticket_list   = cache.ticket_list
      @redirect()
    else
      App.Com.ajax(
        type:       'GET'
        url:        '/api/ticket_overviews'
        data:
          view:      @view
          array:     true
        processData: true
        success:     @load
      )

  load: (data) =>
    @ticket_list   = data.ticket_list
    @tickets_count = data.tickets_count
#    App.Store.write( data )
    @redirect()

  redirect: =>
    Config['LastOverview']         = @view
    Config['LastOverviewPosition'] = @position
    Config['LastOverviewTotal']    = @tickets_count

    # redirect
    if @direction == 'next'
      if @ticket_list[ @position ] && @ticket_list[ @position ]
        Config['LastOverviewPosition']++
        @navigate 'ticket/zoom/' + @ticket_list[ @position ] + '/nav/true'
      else
        @navigate 'ticket/zoom/' + @ticket_list[ @position - 1 ] + '/nav/true'
    else
      if @ticket_list[ @position - 2 ] && @ticket_list[ @position - 2 ] + '/nav/true'
        Config['LastOverviewPosition']--
        @navigate 'ticket/zoom/' + @ticket_list[ @position - 2 ] + '/nav/true'
      else
        @navigate 'ticket/zoom/' + @ticket_list[ @position - 1 ] + '/nav/true'

Config.Routes['ticket_view/:view/:position/:direction'] = Router
Config.Routes['ticket_view/:view'] = Index
