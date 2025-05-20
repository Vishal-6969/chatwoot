class SupportMailbox < ApplicationMailbox
  include IncomingEmailValidityHelper

  attr_accessor :channel, :account, :inbox, :conversation, :processed_mail

  before_processing :find_email_channel,
                    :load_account_from_channel,
                    :load_inbox_from_channel,
                    :decorate_incoming_mail

  def process
    Rails.logger.info "[NeuraChat::SupportMailbox] Processing email #{mail.message_id} from #{original_sender_email} to #{mail.to} with subject: #{mail.subject}"

    # Skip invalid or auto-generated emails
    return unless valid_incoming_email?

    ActiveRecord::Base.transaction do
      find_or_initialize_contact
      find_or_create_conversation
      create_message
      add_attachments_to_message
    end
  end

  private

  # Attempts to identify the email channel based on recipient address
  def find_email_channel
    @channel = EmailChannelFinder.new(mail).perform if @channel.blank?
    raise 'NeuraChat: Email channel or inbox not found' if @channel.nil?

    @channel
  end

  # Loads the account tied to the identified email channel
  def load_account_from_channel
    @account = @channel.account
  end

  # Loads the inbox tied to the identified email channel
  def load_inbox_from_channel
    @inbox = @channel.inbox
  end

  # Decorates the raw email object with context-specific presentation
  def decorate_incoming_mail
    @processed_mail = MailPresenter.new(mail, @account)
  end

  # Extracts sender's email address in lowercase
  def original_sender_email
    @processed_mail.original_sender&.downcase
  end

  # Attempts to find an existing contact or creates a new one if not found
  def find_or_initialize_contact
    @contact = @inbox.contacts.from_email(original_sender_email)

    if @contact.present?
      @contact_inbox = ContactInbox.find_by(inbox: @inbox, contact: @contact)
    else
      create_contact
    end
  end

  # Looks up an existing conversation using the In-Reply-To header
  def find_conversation_by_in_reply_to
    return if in_reply_to_header.blank?

    @account.conversations.where("additional_attributes->>'in_reply_to' = ?", in_reply_to_header).first
  end

  # Extracts the value from the `In-Reply-To` header
  def in_reply_to_header
    mail['In-Reply-To']&.value
  end

  # Builds a new conversation if none exists for the In-Reply-To message
  def find_or_create_conversation
    @conversation = find_conversation_by_in_reply_to

    return if @conversation.present?

    @conversation = Conversation.create!(
      account_id: @account.id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: {
        in_reply_to: in_reply_to_header,
        source: 'email',
        mail_subject: @processed_mail.subject,
        initiated_at: {
          timestamp: Time.now.utc
        }
      }
    )
  end

  # Derives a default contact name when none is explicitly provided
  def identify_contact_name
    processed_mail.sender_name || processed_mail.from.first.split('@').first
  end
end
