class Membership < ActiveRecord::Base
  include HasVolume

  validates_presence_of :group, :user, :volume
  validates_uniqueness_of :user_id, scope: :group_id

  belongs_to :group, counter_cache: true
  belongs_to :user, counter_cache: true
  belongs_to :inviter, class_name: 'User'
  has_many :events, as: :eventable, dependent: :destroy

  scope :active, -> { published.where(is_suspended: false) }
  scope :suspended, -> { where(is_suspended: true) }
  scope :archived, lambda { where('archived_at IS NOT NULL') }
  scope :published, lambda { where(archived_at: nil) }
  scope :sorted_by_group_name, -> { joins(:group).order('groups.full_name') }
  scope :chronologically, -> { order('created_at asc') }

  scope :for_group, lambda {|group| where(group_id: group)}
  scope :admin, -> { where(admin: true) }

  delegate :name, :email, to: :user, prefix: :user
  delegate :parent, to: :group, prefix: :group, allow_nil: true
  delegate :name, :full_name, to: :group, prefix: :group
  delegate :admins, to: :group, prefix: :group
  delegate :name, to: :inviter, prefix: :inviter, allow_nil: true

  after_destroy :leave_subgroups_of_hidden_parents

  def suspend!
    update_attribute(:is_suspended, true)
    subgroup_memberships.each(&:suspend!)
  end

  def subgroup_memberships
    Membership.where(group_id: group.subgroup_ids, user_id: user_id)
  end

  def make_admin!
    update_attribute(:admin, true)
  end

  def remove_admin!
    update_attribute(:admin, false)
  end

  def group_has_multiple_admins?
    group.admins.count > 1
  end

  def user_name_or_email
    return user_name ? user_name : user_email
  end

  private
  def leave_subgroups_of_hidden_parents
    return if group.nil? #necessary if group is missing (as in case of production data)
    return unless group.is_hidden_from_public?
    group.subgroups.each do |subgroup|
      subgroup.memberships.where(user_id: user.id).destroy_all
    end
  end
end
