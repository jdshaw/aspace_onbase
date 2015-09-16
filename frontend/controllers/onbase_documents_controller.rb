class OnbaseDocumentsController < ApplicationController

  # FIXME: use proper permission here
  set_access_control  "view_repository" => [:index, :show],
                      "manage_repository" => [:new, :edit, :create, :update, :merge, :delete]



  def index
    @search_data = Search.global({"sort" => "title_sort asc"}.merge(params_for_backend_search.merge({"facet[]" => SearchResultData.BASE_FACETS})),
                                 "onbase_document")
  end

  def show
    @onbase_document = JSONModel(:onbase_document).find(params[:id])
  end

  def new
    @onbase_document = JSONModel(:onbase_document).new._always_valid!

    raise "Can only create an OnBase document from within the context of another record" if !inline?

    render_aspace_partial :partial => "onbase_documents/new"
  end

  def edit
    @onbase_document = JSONModel(:onbase_document).find(params[:id])
  end

  def create
    file = params[:onbase_document][:file]

    File.open(file.tempfile) do |fh|
      response = JSONModel::HTTP.post_form("/onbase_upload",
                                           {
                                             'file' => UploadIO.new(fh, file.content_type, file.original_filename),
                                             'document_type' => params[:onbase_document][:name]
                                           },
                                           :multipart_form_data)

      render :json => ASUtils.json_parse(response.body)
    end
  end

  def update
    handle_crud(:instance => :onbase_document,
                :model => JSONModel(:onbase_document),
                :obj => JSONModel(:onbase_document).find(params[:id]),
                :on_invalid => ->(){ return render :action => :edit },
                :on_valid => ->(id){
                  flash[:success] = I18n.t("plugins.onbase_document._frontend.messages.updated")
                  redirect_to :controller => :onbase_documents, :action => :edit, :id => id
                })
  end

  def delete
    onbase_document = JSONModel(:onbase_document).find(params[:id])
    onbase_document.delete

    flash[:success] = I18n.t("plugins.onbase_document._frontend.messages.deleted", JSONModelI18nWrapper.new(:onbase_document => onbase_document))
    redirect_to(:controller => :onbase_documents, :action => :index, :deleted_uri => onbase_document.uri)
  end

end
