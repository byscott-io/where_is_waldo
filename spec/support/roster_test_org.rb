# frozen_string_literal: true

# Minimal org/container double: an id plus a `users` AR scope. Stands in for an
# app's Account/Organization so the roster can be exercised without adding an
# org model to the dummy app.
class RosterTestOrg
  attr_reader :id

  def initialize(id:, members:)
    @id = id
    @members = members
  end

  def users
    @members
  end
end
