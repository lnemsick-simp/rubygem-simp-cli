require_relative 'item'

module Simp::Cli::Config

  # mixin that provides common logic for safe_apply()
  module SafeApplying
    def safe_apply
      # set skip reason if we are not allowed to apply as
      # an unpriviledged user and we are not already
      # skipping for some other reason
      unless @allow_user_apply
        if ENV.fetch('USER') != 'root'
          @skip_apply = true
          @skip_apply_reason = '[**user is not root**]' unless @skip_apply_reason
        end
      end

      action = @description.split("\n")[0]

      if @skip_apply
        @applied_status = :skipped
        notice( "(Skipping apply#{skip_apply_reason})", [status_color, :BOLD], " #{action}" )
      else
        notice( ">> Applying:", [:GREEN, :BOLD], " #{action}... " ) # ending space prevents \n
        info('') # add \n after 'Applying:...' when info logging is enabled
        begin
          apply
          notice( "#{@applied_status.to_s.capitalize}", [status_color, :BOLD] )
          if @applied_status == :failed
            if @die_on_apply_fail
              raise ApplyError.new(apply_summary)
            else
              # as a courtesy, pause briefly to give user time to see the
              # error message logged by derived class, before moving on
              pause(:error)
            end
          end

        # Pass up the stack exceptions that may indicate the user has
        # interrupted execution
        rescue EOFError, SignalException => e
          raise
        # Pass up the stack detected software errors or ApplyErrors
        rescue InternalError,ApplyError => e
          raise
        # Handle any other exceptions generated by the apply()
        rescue Exception => e
          @applied_status = :failed
          error( "#{@applied_status.to_s.capitalize}:", [status_color, :BOLD] )
          if @die_on_apply_fail
            # Some failures should be punished by death
            raise ApplyError.new(e.message)
          else
            error( "#{e.message.to_s.gsub( /^/, '    ' )}", [status_color] )
          end
        end
      end
      @applied_time = Time.now
    end
  end

  # A special Item that is never interactive, but applies some configuration
  class ActionItem < Item
    include Simp::Cli::Config::SafeApplying

    attr_accessor :applied_status, :applied_time, :applied_detail
    attr_accessor :defer_apply, :skip_apply, :skip_apply_reason
    attr_accessor :die_on_apply_fail, :allow_user_apply
    attr_reader   :category

    # ActionItem categories in the order in which they should be
    # applied, when deferred until after all data has been gathered.
    # FIXME Should rework so that derived ActionItems can't
    #       set this to some other value!
    SORTED_CATEGORIES = [
      :system,            # action to configure general system settings
      :puppet_global,     # action to configure global Puppet properties
      :puppet_env,        # action to configure the SIMP environment
      :puppet_env_server, # action to configure the SIMP server in the SIMP environment
      :other,             # miscellaneous configuration action
      :sanity_check,      # action to check for possible system problems
                          #   (YUM repo issues, user lockout issues, etc.)
      :answers_writer     # action to write out the answers file
    ]

    def initialize(puppet_env_info = DEFAULT_PUPPET_ENV_INFO)
      super(puppet_env_info)
      @applied_status    = :unattempted  # status of an applied change
      @applied_time      = nil           # time at which applied change completed
      @applied_detail    = nil           # details about the apply to be conveyed to user
      @defer_apply       = true          # defer the apply;  when false, the action
                                         # item must be executed immediately
      @skip_apply        = false         # skip the apply
      @skip_apply_reason = nil           # optional description of reason for skipping the apply
      @data_type         = :none         # carries no data
      @die_on_apply_fail = false         # halt simp config if apply fails
      @allow_user_apply  = false         # allow non-superuser to apply

      @category          = :other        # category which can be used to group actions when applied
                                         # see SORTED_CATEGORIES above for recognized categories

      # TODO Should just be able to use module paths from @puppet_env_info,
      # because we have ensured the SIMP environment is place before attempting
      # the 'simp config' questionnaire. The only reason for using the SIMP
      # module install path, would be if the Item to set up the network was
      # split out in its own command (possible FUTURE work) and executed
      # before the SIMP environment was in place.
      module_path = @puppet_env_info[:puppet_config]['modulepath']
      if File.directory?(Simp::Cli::SIMP_MODULES_INSTALL_PATH)
        module_path += ":#{Simp::Cli::SIMP_MODULES_INSTALL_PATH}"
      end
      #FIXME allow puppet digest algorithm to be configurable
      @puppet_apply_cmd = [
        'puppet apply',
        "--modulepath=#{module_path}",
        "--digest_algorithm=#{Simp::Cli::PUPPET_DIGEST_ALGORITHM}"
      ].join(' ')
    end

    # internal method to change the system (returns the result of the apply)
    def apply; nil; end

    # don't be interactive!
    def validate( x );                             true; end
    def query;                                     nil;  end
    def print_summary;                             nil;  end
    def to_yaml_s( include_auto_warning = false ); nil;  end

    def status_color
      case (@applied_status)
      when :succeeded
        color = :GREEN
      when :unattempted, :skipped, :unnecessary
        color = :MAGENTA
      when :deferred  # operator intervention recommended
        color = :YELLOW
      when :failed
        color = :RED
      else
        color = :RED
      end
      color
    end
  end
end
