# Using Git for CLUSTER1

First, you want to get a local "clone" of the main repo (i.e., the latest and greatest).
```
git clone https://github.com/Catskan/resources.git
```

This command makes a local directory called `cluster1`
```
cd resources

git status
```


The above steps are typically only needed once to setup a client to work. If you need to setup a new client to have the git repo working, you follow the same steps above.

# Authentication

Each command that reaches out to the remote server will prompt for authentication. There are many ways to setup "one-time" authentication, but I'm only showing you one.
```
git config --global credential.helper store
```

When you execute the next command that reaches the git server, you will be prompted for username/password. It will save them in this client so you will not be prompted again.


# Workflow for a specific task

1. Refresh your remotes so you have the latest and greatest:

    ```
    > git fetch --all
    Fetching origin
    Fetching resources.user
    ```

2. Create a local branch from the latest origin
    ```
    git checkout -b my-new-branch origin/main
    ```

3. Make your changes to the files; test locally if you can; 

    ```
    > git status
    On branch my-new-branch
    Your branch is up to date with 'origin/main'.

    Changes not staged for commit:
      (use "git add <file>..." to update what will be committed)
      (use "git restore <file>..." to discard changes in working directory)
      modified:   README.md

    Untracked files:
      (use "git add <file>..." to include in what will be committed)
      git-help.md

    no changes added to commit (use "git add" and/or "git commit -a")

    ```

    The above example shows 1 modified file and 1 untracked file. In either case, you use the `git add <file>` to "stage" it to prepare for the commit. I'm ignoring the README.md file change.
    ```
    > git add git-help.md
    > git restore README.md

    > git status
    On branch origin/main
    Your branch is up to date with 'origin/main'.

    Changes to be committed:
      (use "git restore --staged <file>..." to unstage)
      new file:   git-help.md

    ```

4. Commit your changes locally

    This action will cause an editor to prompt your for the description of the changes.
    ```
    > git commit -m "commit description"
    > Save the file
    [my-new-branch 4c3e1ec] commit description
    1 file changed, 121 insertions(+)
    create mode 100644 git-help.md
    ```

5. Push your changes to

    Pushing your changes to your fork does a couple of things. First, it actually makes a new branch on the server. Second, it associates the branch on the server with your local branch so that future commits can be pushed to the correct spot.

    ```
    > git push --set-upstream origin my-new-branch
    Enumerating objects: 4, done.
    Counting objects: 100% (4/4), done.
    Delta compression using up to 8 threads
    Compressing objects: 100% (3/3), done.
    Writing objects: 100% (3/3), 1.44 KiB | 367.00 KiB/s, done.
    Total 3 (delta 1), reused 0 (delta 0)
    remote: Analyzing objects... (3/3) (58 ms)
    remote: Storing packfile... done (52 ms)
    remote: Storing index... done (47 ms)
    To https://github.com/Catskan/cluster1.git
    * [new branch]      my-new-branch -> my-new-branch
    Branch 'VX-124_work_on_repo_help' set up to track remote branch 'Vmy-new-branch' from 'Catskan'.
    ```
    
    It's good practice to name the branch on your remote in the same way as you have it locally so you can keep track. This convention can be discarded when we start playing with multiple branches for the same ticket, but that's a problem for future us.

6. Create a Pull Request (PR) from the Web UI

    When you refresh the Web UI, it will prompt you that you have pushed a new branch and have a button to "Create Pull Request".  If that's not shown, navigate to the branches on your fork and create the pull request from there: https://github.com/Catskan/resources/branches.
    These are the values for creating a PR:

    **Name**: Short name

    **Description**: Describe the work doing in this branch
  

7. Update PR with more changes

  ***See Steps 3 to 5***

    ```
    > git push
    Enumerating objects: 13, done.
    Counting objects: 100% (13/13), done.
    Delta compression using up to 8 threads
    Compressing objects: 100% (10/10), done.
    Writing objects: 100% (10/10), 4.58 KiB | 1.14 MiB/s, done.
    Total 10 (delta 5), reused 0 (delta 0)
    remote: Analyzing objects... (10/10) (39 ms)
    remote: Storing packfile... done (60 ms)
    remote: Storing index... done (78 ms)
    To https://github.com/martellotech/cluster1.git
      4c3e1ec..8e5a1a6  VX-124_work_on_repo_help -> VX-124_work_on_repo_help
    ```

8. Merge PR

    This is done in the UI. It appears we all have permission to merge into *origin*. You perform the merge by "Completing" the PR.  There are several options here, but I suggest we use the following ones:

    **Merge Type: Squash merge**
    Merge all commits to only a final one

    **Customize merge commit message = true**
    Description or resume of the PR


## Rebasing your working branch 

The above workflow is typical. However, since your teammates will be working asynchronously with you, they may merge changes into **master** that affect your work. In those cases, you will need to **rebase** your branch on the latest master.  In most cases, this can be done automatically. In some cases, git gets confused and you have to help it. I'll describe the easy case here.

First, you want to commit any local changes so that your local version is sane.

Next, you **pull** the changes and rebase your branch to the latest origin.

```
> git pull --rebase origin main
From https://github.com/martellotech/cluster1.git
 * branch            master     -> FETCH_HEAD
Current branch VX-124_work_on_repo_help is up to date.
```

There is some description of difference between **rebase** and **merge** [here](https://www.freecodecamp.org/news/an-introduction-to-git-merge-and-rebase-what-they-are-and-how-to-use-them-131b863785f/).


## Squashing Commits

Some of the issues with rebasing come from the fact that the DevOps web page creates a commit every time you save a file.  That means you end up with hundreds of commits in a branch when 2 or 3 would be sufficient.  The following steps assumes you have a branch locally AND remotely with the same name.

First, do a soft reset to get back to the origin/master. It leaves all your changes locally (soft), but git thinks you're back to origin/master.
```
git fetch --all
git reset --soft origin/master
```

Now, commit all the changes as if it were 1 single commit
```
git add -A && git commit -m "comment to summarize all 100s of commits"
```

Lastly, push (and force overwrite) of your local branch to your remote (the branch and remote are examples below):
```
git push --force origin VX-184_geoff_fix_conflict
```