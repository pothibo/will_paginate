# encoding: utf-8
require 'will_paginate/core_ext'
require 'will_paginate/i18n'
require 'will_paginate/deprecation'

module WillPaginate
  # = Will Paginate view helpers
  #
  # The main view helper is +will_paginate+. It renders the pagination links
  # for the given collection. The helper itself is lightweight and serves only
  # as a wrapper around LinkRenderer instantiation; the renderer then does
  # all the hard work of generating the HTML.
  module ViewHelpers
    class << self
      # Write to this hash to override default options on the global level:
      #
      #   WillPaginate::ViewHelpers.pagination_options[:page_links] = false
      #
      attr_accessor :pagination_options
    end

    # default view options
    self.pagination_options = Deprecation::Hash.new \
      :class          => 'pagination',
      :previous_label => nil,
      :next_label     => nil,
      :inner_window   => 4, # links around the current page
      :outer_window   => 1, # links around beginning and end
      :link_separator => ' ', # single space is friendly to spiders and non-graphic browsers
      :param_name     => :page,
      :params         => nil,
      :page_links     => true,
      :container      => true

    label_deprecation = Proc.new { |key, value|
      "set the 'will_paginate.#{key}' key in your i18n locale instead of editing pagination_options" if defined? Rails
    }
    pagination_options.deprecate_key(:previous_label, :next_label, &label_deprecation)
    pagination_options.deprecate_key(:renderer) { |key, _| "pagination_options[#{key.inspect}] shouldn't be set globally" }

    include WillPaginate::I18n

    # Returns HTML representing page links for a WillPaginate::Collection-like object.
    # In case there is no more than one page in total, nil is returned.
    # 
    # ==== Options
    # * <tt>:class</tt> -- CSS class name for the generated DIV (default: "pagination")
    # * <tt>:previous_label</tt> -- default: "« Previous"
    # * <tt>:next_label</tt> -- default: "Next »"
    # * <tt>:page_links</tt> -- when false, only previous/next links are rendered (default: true)
    # * <tt>:inner_window</tt> -- how many links are shown around the current page (default: 4)
    # * <tt>:outer_window</tt> -- how many links are around the first and the last page (default: 1)
    # * <tt>:separator</tt> -- string separator for page HTML elements (default: single space)
    # 
    # HTML options:
    # * <tt>:class</tt> -- CSS class name for the generated DIV (default: "pagination")
    # * <tt>:container</tt> -- toggles rendering of the DIV container for pagination links, set to
    #   false only when you are rendering your own pagination markup (default: true)
    # * <tt>:id</tt> -- HTML ID for the container (default: nil). Pass +true+ to have the ID
    #   automatically generated from the class name of objects in collection: for example, paginating
    #   ArticleComment models would yield an ID of "article_comments_pagination".
    # * <tt>:remote</tt> -- sets to true the data-remote or remote attribute, depending of the inplementation of link_to
    #
    # Advanced options:
    # * <tt>:param_name</tt> -- parameter name for page number in URLs (default: <tt>:page</tt>)
    # * <tt>:params</tt> -- additional parameters when generating pagination links
    #   (eg. <tt>:controller => "foo", :action => nil</tt>)
    # * <tt>:renderer</tt> -- class name, class or instance of a link renderer (default in Rails:
    #   <tt>WillPaginate::ActionView::LinkRenderer</tt>)
    # * <tt>:page_links</tt> -- when false, only previous/next links are rendered (default: true)
    # * <tt>:container</tt> -- toggles rendering of the DIV container for pagination links, set to
    #   false only when you are rendering your own pagination markup (default: true)
    #
    # All options not recognized by will_paginate will become HTML attributes on the container
    # element for pagination links (the DIV). For example:
    # 
    #   <%= will_paginate @posts, :style => 'color:blue' %>
    #
    # will result in:
    #
    #   <div class="pagination" style="color:blue"> ... </div>
    #
    def will_paginate(collection, options = {})
      # early exit if there is nothing to render
      return nil unless collection.total_pages > 1

      options = WillPaginate::ViewHelpers.pagination_options.merge(options)

      options[:previous_label] ||= will_paginate_translate(:previous_label) { '&#8592; Previous' }
      options[:next_label]     ||= will_paginate_translate(:next_label) { 'Next &#8594;' }

      # get the renderer instance
      renderer = case options[:renderer]
      when nil
        raise ArgumentError, ":renderer not specified"
      when String
        klass = if options[:renderer].respond_to? :constantize then options[:renderer].constantize
          else Object.const_get(options[:renderer]) # poor man's constantize
          end
        klass.new
      when Class then options[:renderer].new
      else options[:renderer]
      end
      # render HTML for pagination
      renderer.prepare collection, options, self
      renderer.to_html
    end

    # Renders a message containing number of displayed vs. total entries.
    #
    #   <%= page_entries_info @posts %>
    #   #-> Displaying posts 6 - 12 of 26 in total
    #
    # The default output contains HTML. Use ":html => false" for plain text.
    def page_entries_info(collection, options = {})
      entry_name = options[:entry_name] ||
        (collection.empty?? 'entry' : collection.first.class.name.underscore.sub('_', ' '))
      
      if collection.total_pages < 2
        case collection.size
        when 0; "No #{entry_name.pluralize} found"
        when 1; "Displaying <b>1</b> #{entry_name}"
        else;   "Displaying <b>all #{collection.size}</b> #{entry_name.pluralize}"
        end
      else
        %{Displaying #{entry_name.pluralize} <b>%d&nbsp;-&nbsp;%d</b> of <b>%d</b> in total} % [
          collection.offset + 1,
          collection.offset + collection.length,
          collection.total_entries
        ]
      end
    end
    
    if respond_to? :safe_helper
      safe_helper :will_paginate, :paginated_section, :page_entries_info
    end
    
    def self.total_pages_for_collection(collection) #:nodoc:
      if collection.respond_to?('page_count') and !collection.respond_to?('total_pages')
        WillPaginate::Deprecation.warn %{
          You are using a paginated collection of class #{collection.class.name}
          which conforms to the old API of WillPaginate::Collection by using
          `page_count`, while the current method name is `total_pages`. Please
          upgrade yours or 3rd-party code that provides the paginated collection}, caller
        class << collection
          def total_pages; page_count; end
        end
      end
      collection.total_pages
    end
  end

  # This class does the heavy lifting of actually building the pagination
  # links. It is used by the <tt>will_paginate</tt> helper internally.
  class LinkRenderer

    # The gap in page links is represented by:
    #
    #   <span class="gap">&hellip;</span>
    attr_accessor :gap_marker
    
    def initialize
      @gap_marker = '<span class="gap">&hellip;</span>'
    end
    
    # * +collection+ is a WillPaginate::Collection instance or any other object
    #   that conforms to that API
    # * +options+ are forwarded from +will_paginate+ view helper
    # * +template+ is the reference to the template being rendered
    def prepare(collection, options, template)
      @collection = collection
      @options    = options
      @template   = template

      # reset values in case we're re-using this instance
      @total_pages = @param_name = @url_string = nil
    end

    # Process it! This method returns the complete HTML string which contains
    # pagination links. Feel free to subclass LinkRenderer and change this
    # method as you see fit.
    def to_html
      links = @options[:page_links] ? windowed_links : []
      # previous/next buttons
      links.unshift page_link_or_span(@collection.previous_page, 'disabled prev_page', @options[:previous_label])
      links.push    page_link_or_span(@collection.next_page,     'disabled next_page', @options[:next_label])
      
      html = links.join(@options[:separator])
      html = html.html_safe if html.respond_to? :html_safe
      @options[:container] ? @template.content_tag(:div, html, html_attributes) : html
    end

    # Returns the subset of +options+ this instance was initialized with that
    # represent HTML attributes for the container element of pagination links.
    def html_attributes
      return @html_attributes if @html_attributes
      @html_attributes = @options.except *(WillPaginate::ViewHelpers.pagination_options.keys - [:class])
      # pagination of Post models will have the ID of "posts_pagination"
      if @options[:container] and @options[:id] === true
        @html_attributes[:id] = @collection.first.class.name.underscore.pluralize + '_pagination'
      end
      @html_attributes
    end
    
  protected

    # Collects link items for visible page numbers.
    def windowed_links
      prev = nil

      visible_page_numbers.inject [] do |links, n|
        # detect gaps:
        links << gap_marker if prev and n > prev + 1
        links << page_link_or_span(n, 'current')
        prev = n
        links
      end
    end

    # Calculates visible page numbers using the <tt>:inner_window</tt> and
    # <tt>:outer_window</tt> options.
    def visible_page_numbers
      inner_window, outer_window = @options[:inner_window].to_i, @options[:outer_window].to_i
      window_from = current_page - inner_window
      window_to = current_page + inner_window
      
      # adjust lower or upper limit if other is out of bounds
      if window_to > total_pages
        window_from -= window_to - total_pages
        window_to = total_pages
      end
      if window_from < 1
        window_to += 1 - window_from
        window_from = 1
        window_to = total_pages if window_to > total_pages
      end
      
      visible   = (1..total_pages).to_a
      left_gap  = (2 + outer_window)...window_from
      right_gap = (window_to + 1)...(total_pages - outer_window)
      visible  -= left_gap.to_a  if left_gap.last - left_gap.first > 1
      visible  -= right_gap.to_a if right_gap.last - right_gap.first > 1

      visible
    end
    
    def page_link_or_span(page, span_class, text = nil)
      text ||= page.to_s
      text = text.html_safe if text.respond_to? :html_safe
      
      if page and page != current_page
        classnames = span_class && span_class.index(' ') && span_class.split(' ', 2).last
        page_link page, text, :rel => rel_value(page), :class => classnames, :remote => @options[:remote]
      else
        b = eb = html_key = ''
        sp = ' '
      end

      model_count = collection.total_pages > 1 ? 5 : collection.size
      defaults = ["models.#{model_key}"]
      defaults << Proc.new { |_, opts|
        if model.respond_to? :model_name
          model.model_name.human(:count => opts[:count])
        else
          name = model_key.to_s.tr('_', ' ')
          raise "can't pluralize model name: #{model.inspect}" unless name.respond_to? :pluralize
          opts[:count] == 1 ? name : name.pluralize
        end
      }
      model_name = will_paginate_translate defaults, :count => model_count

      if collection.total_pages < 2
        i18n_key = :"page_entries_info.single_page#{html_key}"
        keys = [:"#{model_key}.#{i18n_key}", i18n_key]

        will_paginate_translate keys, :count => collection.size, :model => model_name do |_, opts|
          case opts[:count]
          when 0; "No #{opts[:model]} found"
          when 1; "Displaying #{b}1#{eb} #{opts[:model]}"
          else    "Displaying #{b}all#{sp}#{opts[:count]}#{eb} #{opts[:model]}"
          end
        end
      else
        i18n_key = :"page_entries_info.multi_page#{html_key}"
        keys = [:"#{model_key}.#{i18n_key}", i18n_key]
        params = {
          :model => model_name, :count => collection.total_entries,
          :from => collection.offset + 1, :to => collection.offset + collection.length
        }
        will_paginate_translate keys, params do |_, opts|
          %{Displaying %s #{b}%d#{sp}-#{sp}%d#{eb} of #{b}%d#{eb} in total} %
            [ opts[:model], opts[:from], opts[:to], opts[:count] ]
        end
      end
    end
  end
end
