# -*- encoding : utf-8 -*-
class Topic < ActiveRecord::Base

  before_validation :set_default_attributes, :on => :create
  before_update  :check_for_moved_forum
  after_update   :set_post_forum_id
  before_destroy :count_user_posts_for_counter_cache
  after_destroy  :update_cached_forum_and_user_counts

  # creator of forum topic
  belongs_to :user
  
  # creator of recent post
  belongs_to :last_user, :class_name => "User"
  
  belongs_to :forum, :counter_cache => true

  has_many :posts,       :order => "#{Post.table_name}.created_at", :dependent => :delete_all
  has_one  :recent_post, :order => "#{Post.table_name}.created_at DESC", :class_name => "Post"
  
  has_many :voices, :through => :posts, :source => :user, :uniq => true
  
  validates_presence_of :user_id, :forum_id, :title
  validates_presence_of :body, :on => :create

  attr_accessor :body
  attr_accessible :title, :body

  attr_readonly :posts_count, :hits
  
  has_permalink :title
  ##acts_as_defensio_article_comment :fields => { :content => :body, 
  #                                      :article => :article, 
  #                                      :author => :author_name,
  #                                      :permalink => :full_permalink }
  #                                      
                                      
  
  # hacks for defensio
  def article
    self
  end
  
  def author_name 
    user.login
  end
  
  def editable_by?(user)
    user && (user.id == user_id || user.moderator? || user.admin?)
  end
  
  def full_permalink
    "http://#{Alonetone.url}/forums/#{permalink}"
  end
  def sticky?
    sticky == 1
  end
  
  def hit!
    self.class.increment_counter :hits, id
  end

  def paged?
    posts_count > Post.per_page
  end
  
  def last_page
    [(posts_count.to_f / Post.per_page.to_f).ceil.to_i, 1].max
  end

  def update_cached_post_fields(post)
    # these fields are not accessible to mass assignment
    if remaining_post = post.frozen? ? recent_post : post
      self.class.update_all(
        [ 'last_updated_at = ?, last_user_id = ?, last_post_id = ?, posts_count = ?', 
          remaining_post.created_at, remaining_post.user_id, remaining_post.id, posts.count ], 
        ['id = ?', id]
      )
    else
      self.destroy
    end
  end
  
  def to_param
    permalink
  end

  def self.replied_to_by(user)
    user.posts.select('distinct posts.topic_id, topics.*').order('topics.last_updated_at DESC').limit(5).joins(:topic)
  end

  def self.popular
    Post.group(:topic).where(['posts.created_at > ?',10.days.ago]).limit(3).order('count_all DESC').count
  end

  def self.replyless
    Topic.limit(3).order('created_at DESC').where(:posts_count => 1)
  end

protected
  
  def set_default_attributes
    self.sticky          ||= 0
    self.last_updated_at ||= Time.now.utc
  end

  def check_for_moved_forum
    old = Topic.find(id)
    @old_forum_id = old.forum_id if old.forum_id != forum_id
    true
  end

  def set_post_forum_id
    return unless @old_forum_id
    posts.update_all :forum_id => forum_id
    Forum.decrement_counter(:topics_count, @old_forum_id)
    Forum.increment_counter(:topics_count, forum_id)
  end
  
  def count_user_posts_for_counter_cache
    @user_posts = posts.group_by { |p| p.user_id }
  end
  
  def update_cached_forum_and_user_counts
    Forum.update_all "posts_count = posts_count - #{posts_count}", ['id = ?', forum_id]
    @user_posts.each do |user_id, posts|
      User.update_all "posts_count = posts_count - #{posts.size}", ['id = ?', user_id]
    end
  end
end
