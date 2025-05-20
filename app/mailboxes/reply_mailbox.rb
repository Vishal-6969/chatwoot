class ReplyMailbox < ApplicationMailbox
  attr_accessor :conversation_uuid, :processed_mail

  # Matches email addresses like: reply+<conversation-uuid>@domain.com
  EMAIL_PART_PATTERN = /^reply\+([0-9a-f]{8}\b-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-\b[0-9a-f]{12})$/i

  before_processing :extract_conversation_uuid_from_address,
                    :locate_conversation

  def process
    return if @conversation.blank?

    decorate_email
    create_message
    add_attachments_to_message
  end

  private

  # Step 1: Extracts conversation UUID from recipient email
  def extract_conversation_uuid_from_address
    @raw_mail = MailPresenter.new(mail)
    return if @raw_mail.mail_receiver.blank?

    @raw_mail.mail_receiver.each do |email|
      username = email.split('@')[0]
      if (match = username.match(ApplicationMailbox::REPLY_EMAIL_UUID_PATTERN))
        @conversation_uuid = match.captures.first
        break
      end
    end
  end

  # Step 2: Locate the conversation either from UUID or In-Reply-To header
  def locate_conversation
    if @conversation_uuid
      find_conversation_by_uuid
    elsif mail.in_reply_to.present?
      find_conversation_by_in_reply_to_header
    end
  end

  def find_conversation_by_uuid
    @conversation = Conversation.find_by(uuid: conversation_uuid)
    log_if_missing(@conversation, conversation_uuid)
  end

  def find_conversation_by_message_id(message_id)
    related_message = Message.find_by(source_id: message_id)
    if related_message.present?
      @conversation = related_message.conversation
      @conversation_uuid = @conversation.uuid
    end
  end

  # Checks for In-Reply-To headers that match the known conversation/message pattern
  def find_conversation_by_in_reply_to_header
    match = nil
    headers = Array(mail.in_reply_to)

    headers.each do |header|
      match = header.match(ApplicationMailbox::CONVERSATION_MESSAGE_ID_PATTERN)
      break if match
    end

    resolve_conversation_from_match(match, headers)
  end

  def resolve_conversation_from_match(match_result, fallback_headers)
    find_conversation_by_uuid_from_header(match_result) if match_result
    find_conversation_by_message_id(fallback_headers) if @conversation.blank?
  end

  def find_conversation_by_uuid_from_header(match_result)
    @conversation_uuid = match_result.captures.first
    find_conversation_by_uuid
  end

  def log_if_missing(resource, uuid)
    unless resource
      Rails.logger.error "[NeuraChat::ReplyMailbox] Could not find conversation with UUID: #{uuid}"
    end
    resource
  end

  # Decorate mail with account-level context
  def decorate_email
    @processed_mail = MailPresenter.new(mail, @conversation.account)
  end
end
