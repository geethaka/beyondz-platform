class Task < ActiveRecord::Base
  include AASM

  belongs_to :assignment
  belongs_to :task_definition
  belongs_to :user
  has_many :files, class_name: 'TaskFile', dependent: :destroy
  has_one :text, class_name: 'TaskText', dependent: :destroy
  has_many :comments

  enum kind: { file: 0, user_confirm: 1, text: 2 }
  enum file_type: { document: 0, image: 1, video: 2, audio: 3 }

  scope :for_assignment, -> (assignment_id) {
    where(assignment_id: assignment_id)
  }
  
  scope :complete, -> { where(tasks: { state: :complete }) }
  scope :incomplete, -> { where.not(tasks: { state: :complete }) }
  scope :required, -> {
    joins(:task_definition)\
    .where(task_definitions: { required: true })
  }
  scope :not_required, -> {
    joins(:task_definition)\
    .where(task_definitions: { required: false })
  }
  scope :require_approval, -> {
    joins(:task_definition)\
    .where(task_definitions: { requires_approval: true })
  }
  scope :do_not_require_approval, -> {
    joins(:task_definition)\
    .where(task_definitions: { requires_approval: false })
  }
  scope :for_display, -> {
    joins(:task_definition).includes(:task_definition)\
    .order('task_definitions.position ASC')
  }
  scope :files, -> { where(kind: Task.kinds[:file]) }
  scope :need_student_attention, -> {
    where(state: [:new, :pending_revision])
  }
  scope :need_coach_attention, -> {
    where(state: [:pending_approval, :pending_revision]) 
  }


  aasm :column => :state do
    state :new, initial: true
    state :pending_approval, :after_enter => :send_to_approver
    state :pending_revision
    state :complete, :after_enter => :post_completion_check

    event :submit do
      transitions :from => :new, :to => :complete,
        :guard => :does_not_require_approval?
      transitions :from => [:new, :pending_revision], :to => :pending_approval
    end

    event :request_revision, :after => :send_back_to_user do
      transitions :from => :pending_approval, :to => :pending_revision
    end

    event :approve do
      transitions :from => :pending_approval, :to => :complete
    end
  end


  ## State machine callbacks

  def send_to_approver
    # request approval from coach
  end

  def send_back_to_user
    # request revision from user
  end

  def post_completion_check
    # if all tasks are complete, notify coach?
    # lock tasks?
    assignment.validate_tasks
  end

  def in_progress?
    [:pending_approval, :pending_revision].include?(state.to_sym)
  end

  def submitted?
    [:pending_approval, :complete].include?(state.to_sym)
  end

  # does task type meet submit requirements
  def ready_to_submit?
    ready_to_submit = true
    if needs_files? || needs_text? || user_confirm?
      ready_to_submit = false
    end

    ready_to_submit
  end

  # is task state ready to submit
  def submittable?
    can_submit = false
    
    if assignment.in_progress?
      if new? || pending_revision?
        can_submit = true
      end
    end

    can_submit
  end

  def requires_approval?
    task_definition.requires_approval? 
  end

  def does_not_require_approval?
    !requires_approval?
  end

  def needs_text?
    text? && text.nil?
  end

  # def needs_user_confirm?
  #   user_confirm? && !submittable?
  # end

  def needs_files?
    file? && (files.count < 1)
  end

  # blank out uploaded file data
  def reset_files
    files.each do |file|
      # if attachment type exists, delete it
      if type_exists?(file_type)
        file.reset(file_type)
      end
    end
  end

  def delete_files
    files.each do |file|
      file.reset(file_type)
      file.destroy
    end
  end

  def next
    return nil if task_definition.position == assignment.tasks.count
    assignment.tasks.for_display.where("task_definitions.position = ?", task_definition.position + 1).first
  end

  def previous
    return nil if task_definition.position == 1
    assignment.tasks.for_display.where("task_definitions.position = ?", task_definition.position - 1).first
  end
end
