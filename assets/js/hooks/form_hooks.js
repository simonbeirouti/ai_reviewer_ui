const FormHooks = {
  ResetOnSuccess: {
    mounted() {
      this.handleEvent("reset_form", () => {
        this.el.reset();
      });
    }
  }
};

export default FormHooks; 