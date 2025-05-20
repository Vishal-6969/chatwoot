module NeuraIncomingEmailValidationHelper
  private

  # Determines whether the incoming email should be processed.
  # Validates that:
  # - The sender address is external and linked to an active account
  # - The email is not an auto-reply
  # - The sender email format is valid
  def valid_incoming_email?
    return false unless external_email_for_active_account?
    return false if auto_reply_message?
    return false unless Devise.email_regexp.match?(@incoming_mail.original_sender)

    true
  end

  # Checks whether the email originates from a valid sender
  # and the associated account is active.
  # Prevents handling of system-generated emails (e.g., platform alerts).
  def external_email_for_active_account?
    return false unless @account.active?
    return false if @incoming_mail.system_notification_from_neurachat?

    true
  end

  # Identifies whether the email is an auto-reply
  # such as vacation responders or delivery failures.
  def auto_reply_message?
    if @incoming_mail.auto_reply?
      Rails.logger.info "[NeuraChat] Skipped auto-reply email"
      true
    else
      false
    end
  end
end
