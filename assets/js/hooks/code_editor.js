const CodeEditor = {
  mounted() {
    // Initialize the editor
    this.initializeEditor();
    
    // Add event listeners
    this.setupEventListeners();
  },

  initializeEditor() {
    // Set initial height to match content
    this.el.style.height = 'auto';
    this.el.style.height = `${this.el.scrollHeight}px`;
  },

  setupEventListeners() {
    // Handle content changes
    this.el.addEventListener("input", (e) => {
      // Adjust height
      e.target.style.height = 'auto';
      e.target.style.height = `${e.target.scrollHeight}px`;
      
      // Send content to server
      this.pushEvent("handle_code_change", { value: e.target.value });
    });

    // Sync scroll between line numbers and textarea
    const lineNumbers = document.querySelector('.line-numbers');
    if (lineNumbers) {
      this.el.addEventListener("scroll", () => {
        lineNumbers.scrollTop = this.el.scrollTop;
      });
    }

    // Handle tab key
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Tab") {
        e.preventDefault();
        const start = this.el.selectionStart;
        const end = this.el.selectionEnd;
        const spaces = "  "; // 2 spaces for indentation
        
        this.el.value = this.el.value.substring(0, start) + spaces + this.el.value.substring(end);
        this.el.selectionStart = this.el.selectionEnd = start + spaces.length;
        
        // Trigger the input event to update the content
        this.el.dispatchEvent(new Event("input"));
      }
    });

    // Handle Ctrl+S or Cmd+S to save
    document.addEventListener("keydown", (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === "s") {
        e.preventDefault();
        this.pushEvent("save_changes", {});
      }
    });
  }
};

export default CodeEditor; 