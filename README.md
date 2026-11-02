# Cut_And_Run_Nextflow

## Creating a New nf-core Pipeline Template

To scaffold a new pipeline using the official `nf-core` template, run:

```bash
nf-core pipelines create
```

Running `nf-core pipelines create` launches an interactive wizard (TUI) to configure the pipeline name, description, author, and template features. It generates the standard `nf-core` directory structure, boilerplate configuration, and initializes a Git repository with the required `TEMPLATE`, `dev`, and `master`/`main` branches for future template synchronization.

You can also pass options directly via the CLI:

```bash
nf-core pipelines create -n <pipeline_name> -d "<description>" -a "<author>"
```

Example for this repository:

```bash
nf-core pipelines create -n cutandrun -d "Nextflow CUT&RUN analysis pipeline for quality control, alignment, peak calling, and reporting" -a "DanHUMassMed"
```


