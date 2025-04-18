const CodeEditor = {
  mounted() {
    this.el.addEventListener("input", (e) => {
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
  }
};

export default CodeEditor; 