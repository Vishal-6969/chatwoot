class ApplicationMailbox < ActionMailbox::Base
  include MailboxHelper

  # Extracts UUID from email addresses like: reply+<UUID>@domain.com
  REPLY_EMAIL_UUID_PATTERN = /^reply\+([0-9a-f]{8}\b-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-\b[0-9a-f]{12})$/i

  # Matches emails with conversation metadata in the `in-reply-to` header:
  # Example: conversation/xyz/messages/123@inbound.domain.com
  CONVERSATION_MESSAGE_ID_PATTERN = %r{conversation/([a-zA-Z0-9-]*?)/messages/(\d+?)@(\w+\.\w+)}

  # Route to ReplyMailbox: if email is a reply to an existing conversation
  routing(
    ->(inbound_mail) {
      valid_recipient_address?(inbound_mail) &&
        (uuid_reply_email?(inbound_mail) || in_reply_to_header_matches?(inbound_mail))
    } => :reply
  )

  # Route to SupportMailbox: if email starts a new conversation via email channel
  routing(
    ->(inbound_mail) {
      valid_recipient_address?(inbound_mail) &&
        EmailChannelFinder.new(inbound_mail.mail).perform.present?
    } => :support
  )

  # Catch-all: send unmatched emails to NeuraDefaultMailbox
  routing(all: :default)

  class << self
    # Checks if the 'In-Reply-To' header matches an existing conversation pattern or source ID
    def in_reply_to_header_matches?(inbound_mail)
      in_reply_to = inbound_mail.mail.in_reply_to

      in_reply_to.present? && (
        conversation_message_id_match?(in_reply_to) || Message.exists?(source_id: in_reply_to)
      )
    end

    # Matches conversation format in 'In-Reply-To'
    def conversation_message_id_match?(in_reply_to)
      Array.wrap(in_reply_to).any? { _1.match?(CONVERSATION_MESSAGE_ID_PATTERN) }
    end

    # Matches the 'reply+UUID@...' pattern for routed reply handling
    def uuid_reply_email?(inbound_mail)
      inbound_mail.mail.to&.any? do |email|
        local_part = email.split('@')[0]
        local_part.match?(REPLY_EMAIL_UUID_PATTERN)
      end
    end

    # Validates that the email's `to` header is structurally correct
    def valid_recipient_address?(inbound_mail)
      address_class = inbound_mail.mail.to&.class
      return true if address_class == Mail::AddressContainer

      Rails.logger.error "[NeuraChat] Malformed email 'to' header: #{inbound_mail.mail.to}"
      false
    end
  end
end
