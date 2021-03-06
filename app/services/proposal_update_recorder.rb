class ProposalUpdateRecorder
  include ValueHelper

  def initialize(client_data)
    @client_data = client_data
  end

  def run
    comment_texts = changed_attributes.map do |key, _value|
      update_comment_format(key)
    end

    if comment_texts.any?
      create_comment(comment_texts)
    end
  end

  private

  attr_accessor :client_data

  def changed_attributes
    @changed_attributes ||= client_data.changed_attributes.except(:updated_at)
  end

  def update_comment_format(key)
    "#{bullet}*#{property_name(key)}* was changed " + former_value(key) + "to #{new_value(key)}"
  end

  def bullet
    if changed_attributes.length > 1
      "- "
    else
      ""
    end
  end

  def property_name(key)
    client_data.class.human_attribute_name(key)
  end

  def former_value(key)
    value = property_to_s(client_data.send(key + "_was"))

    if value.present?
      "from #{value} "
    else
      ""
    end
  end

  def new_value(key)
    value = property_to_s(client_data[key])

    if value.empty?
      "*empty*"
    else
      value
    end
  end

  def create_comment(comment_texts)
    if client_data.approved?
      comment_texts << "_Modified post-approval_"
    end

    proposal.comments.create(
      comment_text: comment_texts.join("\n"),
      update_comment: true,
      user: client_data.modifier || client_data.requester
    )
  end

  def proposal
    client_data.proposal
  end
end
