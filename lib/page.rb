
require 'rdiscount'
#
class Page
  include DataMapper::Resource
  # Properties
  property :id,           Serial
  property :title,        String,  default: 'Title'
  property :permalink,    String,  default: proc { |r, _p| r.slug }
  property :content,      Text, default: 'Enter some content here'
  property :created_at, DateTime # , :default => Time.now
  property :updated_at, DateTime
  property :published_at, DateTime
  property :position,     Integer, default: proc { |r, _p| r.siblings.empty? ? 1 : r.siblings.size.next }
  property :parent_id,    Integer
  property :show_title,   Boolean, default: true

  # Callbacks
  before :save do
    old_permalink = permalink
    new_permalink = parent_id ? parent.permalink + '/' + slug : slug
    if new_permalink != old_permalink
      self.permalink = new_permalink
      @new_permalink = true
    end
  end

  after :save do
    if @new_permalink && children?
      children.each(&:save)
      @new_permalink = false
    end
  end

  # Validations
  validates_uniqueness_of :permalink

  # Default order
  default_scope(:default).update(order: [:position])

  # Associations
  belongs_to  :parent,    model: 'Page',   child_key: [:parent_id]
  has n,      :children,  model: 'Page',   child_key: [:parent_id]

  # Some named_scopes
  def self.published
    all(:published_at.not => nil)
  end

  def self.roots
    all(parent_id: nil)
  end

  def self.recent(number = 1)
    all(order: [:created_at.desc], limit: number)
  end

  def self.random(_number = 1)
    # not currently working - now way to get random records in dm
    # all(:order => ['RAND()'], :limit => number)
  end

  # returns the level of the page, 1 = root
  def level
    level = 1
    page = self
    while page.parent
      level = level.next
      page = page.parent
    end
    level
  end

  def ancestors
    page = self
    pages = []
    pages << page = page.parent while page.parent
    pages
  end

  # Returns the root node of the tree.
  def root
    page = self
    page = page.parent while page.parent
    page
  end

  def self_and_siblings
    Page.all(parent_id: parent_id)
  end

  def siblings
    Page.all(:parent_id => parent_id, :id.not => id)
  end

  # Returns a page's permalink based on its title
  def slug
    title.downcase.gsub(/\W/, '-').squeeze('-').chomp('-')
  end

  # Returns a summary of the page
  def summary
    content[0, 400]
  end

  # useful paths for the page
  def path
    '/' + permalink
  end

  def edit_path
    '/page/' + id.to_s
  end

  def delete_path
    "/page/#{id}/delete"
  end

  def new_path
    '/new/page'
  end

  def new_child_path
    '/new/page?section=' + id.to_s
  end

  def new_sibling_path
    '/new/page?section=' + parent_id.to_s
  end

  # test if a page is a root page
  def root?
    parent_id.nil?
  end

  # test if a page is published or not
  def published?
    true unless published_at.nil?
  end

  # test if a page is a draft or not
  def draft?
    published_at.nil?
  end

  # test if a page has children or not
  def children?
    !children.empty?
  end
end

# Page routes

# Show home page
get '/' do
  @page = Page.roots.published.first
  if @page
    erb :'milkshake/show', layout: :'milkshake/layout'
  else
    redirect '/pages'
  end
end

# admin dashboard/index
get '/pages' do
  @pages = admin? ? Page.roots : Page.roots.published
  erb :'milkshake/index', layout: :'milkshake/layout'
end

# new
get '/new/page' do
  protected!
  @page = Page.new(parent_id: params[:section])
  erb :'milkshake/new', layout: :'milkshake/layout'
end

# create
post '/new/page' do
  protected!
  @page = Page.new(params[:page])
  @page.show_title = false unless params[:show_title]
  @page.published_at = params[:publish] ? Time.now : nil
  if @page.save
    status 201
    redirect @page.path
  else
    status 412
    redirect '/pages'
  end
end

# edit
get '/page/:id' do
  protected!
  @page = Page.get(params[:id])
  if @page
    erb :'milkshake/edit', layout: :'milkshake/layout'
  else
    redirect '/pages'
  end
end

# update
put '/page/:id' do
  protected!
  @page = Page.get(params[:id])
  @page.show_title = false unless params[:show_title]
  @page.published_at = params[:publish] ? Time.now : nil
  if @page.update_attributes(params[:page])
    status 201
    redirect @page.path
  else
    status 412
    redirect '/pages'
  end
end

# delete confirmation
get '/page/:id/delete' do
  protected!
  @page = Page.get!(params[:id])
  erb :'milkshake/delete', layout: :'milkshake/layout'
end

# delete
delete '/page/:id' do
  protected!
  @page = Page.get!(params[:id])
  @page.children.destroy! if @page.children
  @page.destroy
  redirect '/pages'
end

# show - should come last in order
get '/*' do
  @page = Page.first(permalink: params[:splat])
  raise error(404) unless @page
  protected! if @page.draft?
  erb :'milkshake/show', layout: :'milkshake/layout'
end

# errors
error 404 do
  erb :'milkshake/page_missing', layout: :'milkshake/layout'
end

helpers do
  def page_title
    if @title
      SITE_NAME + ' * ' + @title
    elsif @page
      SITE_NAME + ' * ' + @page.title
    else
      SITE_NAME
    end
  end

  def css(*stylesheets)
    stylesheets.inject([]) do |html, stylesheet|
      html << "<link rel=\"stylesheet\" type=\"text/css\" media=\"screen, projection\" href=\"/stylesheets/#{stylesheet}.css\" />"
    end.join("\n")
  end

  def js(*scripts)
    scripts.inject([]) do |html, script|
      html << "<script src=\"#{script}.js\" type=\"text/javascript\"></script>"
    end.join("\n")
  end

  def breadcrumbs(page = @page, separator = '>>')
    pages = page.ancestors.reverse + [page]
    separator = ' ' + separator + ' '
    pages.inject('<div class="breadcrumbs">') do |list, crumb|
      list << "<a href=\"#{crumb.path}\">#{crumb.title}</a>" + separator
    end.chomp(separator).concat('</div>')
  end

  def list_of_links(pages = :roots, opts = {})
    pages = @page.respond_to?(pages.to_sym) ? @page.send(pages.to_sym).published : Page.published.roots
    attributes = ''
    opts.each { |key, value| attributes << key.to_s << '="' << value << '" ' }
    output = "<ul #{attributes}>"
    pages.each { |page| output << "\n<li><a href=\"#{page.path}\">#{page.title}</a></li>" }
    output << "\n</ul>"
  end

  def shakedown(text)
    text.gsub!(/(?:%\s*)(\w+)(?:\s*[(\r\n)%])/) do |match|
      if @page && @page.respond_to?(Regexp.last_match(1).to_sym)
        @page.send(Regexp.last_match(1).to_sym).to_s
      else
        match
      end
    end
    # text.gsub!(/(%)(=)?(\s*)(.*)(%)/,'<%\2 \4 %>')
    text = erb(text, layout: false)
    RDiscount.new(text).to_html
  end
end
