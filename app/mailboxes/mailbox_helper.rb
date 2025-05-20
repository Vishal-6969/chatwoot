module MailboxHelper
  private

  # Creates an incoming email message unless it already exists
  def create_message
    Rails.logger.info "[NeuraChat::MailboxHelper] Creating message with ID: #{processed_mail.message_id}"

    return if @conversation.messages.exists?(source_id: processed_mail.message_id)

    @message = @conversation.messages.create!(
      account_id: @conversation.account_id,
      sender: @conversation.contact,
      content: mail_content&.truncate(150_000),
      inbox_id: @conversation.inbox_id,
      message_type: 'incoming',
      content_type: 'incoming_email',
      source_id: processed_mail.message_id,
      content_attributes: {
        email: processed_mail.serialized_data,
        cc_email: processed_mail.cc,
        bcc_email: processed_mail.bcc
      }
    )
  end

  # Attaches inline and regular files to the created message
  def add_attachments_to_message
    return if @message.blank?

    attachments = processed_mail.attachments.last(Message::NUMBER_OF_PERMITTED_ATTACHMENTS)
    grouped = group_attachments_by_type(attachments)

    process_inline_attachments(grouped[:inline]) if grouped[:inline].present?
    process_regular_attachments(grouped[:regular]) if grouped[:regular].present?

    @message.save!
  end

  # Categorizes attachments into inline (e.g. images) and regular files
  def group_attachments_by_type(attachments)
    inline_attachments = attachments.select do |att|
      mail_content.present? &&
        att[:original].inline? &&
        att[:original].content_type.to_s.start_with?('image/')
    end

    {
      inline: inline_attachments,
      regular: attachments - inline_attachments
    }
  end

  # Handles regular (non-inline) file attachments
  def process_regular_attachments(attachments)
    Rails.logger.info "[NeuraChat::MailboxHelper] Processing regular attachments for message #{processed_mail.message_id}"

    attachments.each do |mail_attachment|
      @message.attachments.new(
        account_id: @conversation.account_id,
        file_type: 'file'
      ).file.attach(mail_attachment[:blob])
    end
  end

  # Embeds inline images into the message HTML and text content
  def process_inline_attachments(attachments)
    Rails.logger.info "[NeuraChat::MailboxHelper] Processing inline attachments for message #{processed_mail.message_id}"

    @html_content = processed_mail.serialized_data.dig(:html_content, :full)
    @text_content = processed_mail.serialized_data.dig(:text_content, :reply)

    attachments.each { |att| embed_inline_image_source(att) }

    @message.content_attributes[:email][:html_content][:full] = @html_content
    @message.content_attributes[:email][:text_content][:full] = @text_content
  end

  # Embeds image URLs based on message format
  def embed_inline_image_source(mail_attachment)
    if @html_content.present?
      upload_inline_image(mail_attachment)
    elsif @text_content.present?
      embed_text_with_inline_image(mail_attachment)
    end
  end

  # Replaces cid: references with real URLs in HTML content
  def upload_inline_image(mail_attachment)
    content_id = mail_attachment[:original].cid
    @html_content.gsub!("cid:#{content_id}", inline_image_url(mail_attachment[:blob]).to_s)
  end

  # Inserts <img> tags into plain text content where applicable
  def embed_text_with_inline_image(mail_attachment)
    filename = mail_attachment[:original].filename
    img_tag = "<img src=\"#{inline_image_url(mail_attachment[:blob])}\" alt=\"#{filename}\">"
    placeholder = "[image: #{filename}]"

    @text_content.include?(placeholder) ?
      @text_content.gsub!(placeholder, img_tag) :
      @text_content += "\n\n#{img_tag}"
  end

  # Returns public URL for inline attachment
  def inline_image_url(blob)
    Rails.application.routes.url_helpers.url_for(blob)
  end

  # Creates or finds a contact and inbox association
  def create_contact
    @contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: processed_mail.original_sender,
      inbox: @inbox,
      contact_attributes: {
        name: identify_contact_name,
        email: processed_mail.original_sender,
        additional_attributes: {
          source_id: "email:#{processed_mail.message_id}"
        }
      }
    ).perform

    @contact = @contact_inbox.contact

    Rails.logger.info "[NeuraChat::MailboxHelper] Contact #{@contact.id} created or found for inbox #{@inbox.id}"
  end

  # Extracts email reply content from text or HTML version
  def mail_content
    if processed_mail.text_content.present?
      processed_mail.text_content[:reply]
    elsif processed_mail.html_content.present?
      processed_mail.html_content[:reply]
    end
  end
end
