require 'tamtam'

class Emailer
  DEFAULT_STYLESHEET_PATH = File.join(File.dirname(__FILE__), '/../template/styles.css').freeze
  TEMPLATE = File.join(File.dirname(__FILE__), '/../template/email.html.erb').freeze
  PARAMETERS = %w[project_path recipient from_address from_alias subject text_message html_message ref_name old_rev new_rev].freeze

  attr_reader :config

  def initialize(config, options = {})
    @config = config || {}
    PARAMETERS.each do |name|
      instance_variable_set("@#{name}".to_sym, options[name.to_sym])
    end
  end

  class << self
    def reset_template
      @template = nil
    end

    def template
      unless @template
        source = IO.read(TEMPLATE)
        begin
          require 'erubis'
           @template = Erubis::Eruby.new(source)
        rescue LoadError
          require 'erb'
          @template = ERB.new(source)
        end
      end
      @template
    end
  end

  def generate_message
    # TODO: do not use @html, simply return value
    @html = TamTam.inline(:document => Emailer.template.result(binding))
  end

  def boundary
    return @boundary if @boundary
    srand
    seed = "#{rand(10000)}#{Time.now}"
    @boundary = Digest::SHA1.hexdigest(seed)
  end

  def stylesheet_string
    stylesheet = config['stylesheet'] || DEFAULT_STYLESHEET_PATH
    IO.read(stylesheet)
  end

  def perform_delivery_smtp(content, smtp_settings)
    settings = { }
    %w(address port domain user_name password authentication enable_tls).each do |key|
      val = smtp_settings[key].to_s.empty? ? nil : smtp_settings[key]
      settings.merge!({ key => val})
    end

    Net::SMTP.start(settings['address'], settings['port'], settings['domain'],
                    settings['user_name'], settings['password'], settings['authentication']) do |smtp|

      smtp.enable_tls if settings['enable_tls']

      smtp.open_message_stream(@from_address, [@recipient]) do |f|
        content.each do |line|
          f.puts line
        end
      end
    end
  end

  def perform_delivery_sendmail(content, options = nil)
    sendmail_settings = {
      'location' => "/usr/sbin/sendmail",
      'arguments' => "-i -t"
    }.merge(options || {})
    command = "#{sendmail_settings['location']} #{sendmail_settings['arguments']}"
    IO.popen(command, "w+") do |f|
      f.write(content.join("\n"))
      f.flush
    end
  end

  def send
    generate_message
    from = quote_if_necessary(@from_alias.empty? ? @from_address : "#{@from_alias} <#{@from_address}>", 'utf-8')
    content = ["From: #{from}",
        "Reply-To: #{from}",
        "To: #{quote_if_necessary(@recipient, 'utf-8')}",
        "Subject: #{quote_if_necessary(@subject, 'utf-8')}",
        "X-Mailer: git-commit-notifier",
        "X-Git-Refname: #{@ref_name}",
        "X-Git-Oldrev: #{@old_rev}",
        "X-Git-Newrev: #{@new_rev}",
        "Mime-Version: 1.0",
        "Content-Type: multipart/alternative; boundary=#{boundary}\n\n\n",
        "--#{boundary}",
        "Content-Type: text/plain; charset=utf-8",
        "Content-Transfer-Encoding: 8bit",
        "Content-Disposition: inline\n\n\n",
        @text_message,
        "--#{boundary}",
        "Content-Type: text/html; charset=utf-8",
        "Content-Transfer-Encoding: 8bit",
        "Content-Disposition: inline\n\n\n",
        @html,
        "--#{boundary}--"]

    if @recipient.empty?
      puts content.join("\n")
      return
    end

    if config['delivery_method'] == 'smtp'
      perform_delivery_smtp(content, @config['smtp_server'])
    else
      perform_delivery_sendmail(content, @config['sendmail_options'])
    end
  end

  # Convert the given text into quoted printable format, with an instruction
  # that the text be eventually interpreted in the given charset.
  def quoted_printable(text, charset)
    text = text.gsub( /[^a-z ]/i ) { quoted_printable_encode($&) }.
                gsub( / /, "_" )
    "=?#{charset}?Q?#{text}?="
  end

  # Convert the given character to quoted printable format, taking into
  # account multi-byte characters (if executing with $KCODE="u", for instance)
  def quoted_printable_encode(character)
    result = ""
    character.each_byte { |b| result << "=%02X" % b }
    result
  end

  # A quick-and-dirty regexp for determining whether a string contains any
  # characters that need escaping.
  CHARS_NEEDING_QUOTING = /[\000-\011\013\014\016-\037\177-\377]/

  # Quote the given text if it contains any "illegal" characters
  def quote_if_necessary(text, charset)
    text = text.dup.force_encoding(Encoding::ASCII_8BIT) if text.respond_to?(:force_encoding)

    (text =~ CHARS_NEEDING_QUOTING) ?
      quoted_printable(text, charset) :
      text
  end
end

