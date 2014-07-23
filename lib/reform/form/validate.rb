# Mechanics for writing to forms in #validate.
module Reform::Form::Validate
  module Update
    # Go through all nested forms and call form.update!(hash).
    def from_hash(*)
      nested_forms do |attr|
        attr.merge!(
          # set parse_strategy: sync> # DISCUSS: that kills the :setter directive, which usually sucks. at least document this in :populator.
          :collection => attr[:collection], # TODO: Def#merge! doesn't consider :collection if it's already set in attr YET.
          :parse_strategy => :sync, # just use nested objects as they are.

          :deserialize => lambda { |object, params, args| object.update!(params) },
        )

        # TODO: :populator now is just an alias for :instance. handle in ::property.
        attr.merge!(:instance => attr[:populator]) if attr[:populator]

        attr.merge!(:instance => lambda { |fragment, *args| Populator::PopulateIfEmpty.new(self, fragment, args).call }) if attr[:populate_if_empty]
      end

      super
    end
  end


  module Populator
    # TODO: this will soon get replaced and simplified.
    class PopulateIfEmpty
      def initialize(*args)
        @fields, @fragment, args = args
        @index = args.first
        @args  = args.last
      end

      def call
        binding = @args.binding
        form    = binding.get

        parent_form =  @args.user_options[:parent_form]
        form_model    = parent_form.model # FIXME: sort out who's responsible for sync.

        return form[@index] if binding.array? and form and form[@index] # TODO: this should be handled by the Binding.
        return if !binding.array? and form
        # only get here when above form is nil.


        if binding[:populate_if_empty].is_a?(Proc)
          model = parent_form.instance_exec(@fragment, @args, &binding[:populate_if_empty]) # call user block.
        else
          model = binding[:populate_if_empty].new
        end

        form  = binding[:form].new(model) # free service: wrap model with Form. this usually happens in #setup.

        if binding.array?
          form_model.send("#{binding.getter}") << model # FIXME: i don't like this, but we have to add the model to the parent object to make associating work. i have to use #<< to stay compatible with AR's has_many API. DISCUSS: what happens when we get out-of-sync here?
          @fields.send("#{binding.getter}")[@index] = form
        else
          form_model.send("#{binding.setter}", model) # FIXME: i don't like this, but we have to add the model to the parent object to make associating work.
          @fields.send("#{binding.setter}", form) # :setter is currently overwritten by :parse_strategy.
        end
      end
    end # PopulateIfEmpty
  end

  # 1. Populate the form object graph so that each incoming object has a representative form object.
  # 2. Deserialize. This is wrong and should be done in 1.
  # 3. Validate the form object graph.
  def validate(params)
    update!(params)

    super() # run the actual validation on self.
  end

  def update!(params)
    deserialize!(params)
  end

private
  def deserialize!(params)
    # using self here will call the form's setters like title= which might be overridden.
    mapper.new(self).extend(Update).from_hash(params, :parent_form => self)
  end
end
