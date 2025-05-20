class Imap::ImapMailbox
  include MailboxHelper
  include IncomingEmailValidityHelper

  attr_accessor :channel, :account, :inbox, :conversation, :processed_mail

  def process(mail, channel)
    @inbound_mail = mail
    @channel = channel

    load_account
    load_inbox
    decorate_incoming_mail

    Rails.logger.info "[NeuraChat::ImapMailbox] Processing email from #{@processed_mail.original_sender} in inbox #{@inbox.id}, message ID: #{@processed_mail.message_id}"

    return unless valid_incoming_email?

    ActiveRecord::Base.transaction do
      find_or_initialize_contact
      find_or_create_conversation
      create_message
      add_attachments_to_message
    end
  end

  private

  def load_account
    @account = @channel.account
  end

  def load_inbox
    @inbox = @channel.inbox
  end

  def decorate_incoming_mail
    @processed_mail = MailPresenter.new(@inbound_mail, @account)
  end

  def in_reply_to
    @processed_mail.in_reply_to
  end

  # Finds conversation by the 'In-Reply-To' header if it matches a known message
  def find_conversation_by_in_reply_to
    return if in_reply_to.blank?

    message = @inbox.messages.find_by(source_id: in_reply_to)
    return @inbox.conversations.find_by(id: message&.conversation_id) if message

    @inbox.conversations.where("additional_attributes->>'in_reply_to' = ?", in_reply_to).first
  end

  # Finds conversation by scanning 'References' headers for known message IDs
  def find_conversation_by_reference_ids
    return if @inbound_mail.references.blank? && in_reply_to.present?

    message = find_message_by_references
    @inbox.conversations.find_by(id: message&.conversation_id) if message
  end

  def find_message_by_references
    Array.wrap(@inbound_mail.references).reverse_each do |message_id|
      message = @inbox.messages.find_by(source_id: message_id)
      return message if message.present?
    end
    nil
  end

  # Finds an existing conversation or creates a new one
  def find_or_create_conversation
    @conversation = find_conversation_by_in_reply_to ||
                    find_conversation_by_reference_ids ||
                    ::Conversation.create!(
                      account_id: @account.id,
                      inbox_id: @inbox.id,
                      contact_id: @contact.id,
                      contact_inbox_id: @contact_inbox.id,
                      additional_attributes: {
                        source: 'email',
                        in_reply_to: in_reply_to,
                        mail_subject: @processed_mail.subject,
                        initiated_at: {
                          timestamp: Time.now.utc
                        }
                      }
                    )
  end

  # Finds or builds a contact from the sender's email
  def find_or_initialize_contact
    @contact = @inbox.contacts.from_email(@processed_mail.original_sender)

    if @contact.present?
      @contact_inbox = ContactInbox.find_by(inbox: @inbox, contact: @contact)
    else
      create_contact
    end
  end

  # Builds a fallback contact name from email if no name is provided
  def identify_contact_name
    processed_mail.sender_name || processed_mail.from.first.split('@').first
  end
end
