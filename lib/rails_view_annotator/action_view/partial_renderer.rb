module RailsViewAnnotator
  # Tells for which formats the partial has been requested.
  def self.extract_requested_formats_from(render_arguments)
    lookup_context = render_arguments[0].lookup_context
    lookup_context.formats
  end

  def self.augment_partial_renderer klass
    stock_render = klass.instance_method :render
    klass.send(:define_method, :render) do |*args|
      inner = stock_render.bind(self).call(*args)

      return unless identifier

      short_identifier = Pathname.new(identifier).relative_path_from Rails.root

      r = /^#{Regexp.escape(Rails.root.to_s)}\/([^:]+:\d+)/
      caller.find { |line| line.match r }
      called_from = context = $1

      descriptor = "#{short_identifier} (from #{called_from})"

      if inner.present?
        comment_pattern = "%{partial}"
        template_formats = RailsViewAnnotator.extract_requested_formats_from(args)
        if template_formats.include?(:text) # Do not render any comments for raw plaintext repsonses
          return inner
        elsif template_formats.include?(:js)
          comment_pattern = "/* begin: %{comment} */\n#{comment_pattern}/* end: %{comment} */"
        elsif template_formats.empty? || template_formats.include?(:html)
          comment_pattern = "<!-- begin: %{comment} -->\n#{comment_pattern}<!-- end: %{comment} -->"
        end

        if Gem::Version.new(Rails.version) < Gem::Version.new(6)
          (comment_pattern % {:partial => inner, :comment => descriptor}).html_safe
        else
          inner.instance_variable_set(:@body, (comment_pattern % {:partial => inner.body, :comment => descriptor}).html_safe)
          inner
        end
      end
    end
    klass.send(:include, InstanceMethods)
  end

  module InstanceMethods
    def identifier
      @template = if Gem::Version.new(Rails.version) < Gem::Version.new(6)
        find_partial
      else
        find_partial(@path, @template_keys)
      end
      @template ? @template.identifier : @path
    end
  end
end
