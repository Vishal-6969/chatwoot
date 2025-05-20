# This mailbox acts as a fallback handler for unmatched inbound emails.
# It currently performs no operations, but can be extended in NeuraChat
# to log, flag, or redirect improperly routed email messages.
class NeuraDefaultMailbox < ApplicationMailbox
  # Processes unmatched emails.
  # This method is intentionally left blank for future use cases.
  def process
    # Example future behavior:
    # Rails.logger.info "[NeuraChat] Received unmatched email in default mailbox"
    # Optionally notify admin or track metrics here.
  end
end
