---
title: Low-level Git commit
categories: Coding
tags: Git
---
Once, I was curious about how Git works and opened the "Pro GIT" book.
In the chapter "[Git Internals - Git Objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects)", you can read that Git is a key-value data storage that operates with Git objects.
The chapter guides you through the process of committing using git hash-object, git update-index, git write-tree, and git commit-tree instead of the familiar git commit.
The book explains one Git command by using other Git commands.
It briefly shows how to create a blob object (one of three kinds) in Ruby.
I was interested in lower levels, so I decided to create a commit without using Git commands at all.

Here I'll try to create a Git repo from scratch with just one initial commit.
The commit will describe a single "file.txt" with literally "Some file content." in it.
The example lines listed here can be copy-pasted into your terminal step-by-step, or you can find the whole bash script at the end of the page.

First, let's put the content in a file.
For not to mix it with the target "file.txt", we'll give it another name:
```bash
echo "Some file content." > file.content
```
Now it's time to create a blob object from the content.
Each object in Git has the same inner structure: `<type> <contentSize><zeroByte><content>`, e.g. `blob 6\0Hello!`.
Calculating content size and zero byte will come in handy for us several times, let's put them into functions.
```bash
size() { wc -c < $1; }
zero() { printf '\0'; }
{ echo -n "blob $(size 'file.content')"; zero; cat file.content; } > blob.bin
```
You may notice that `echo -n` is used here.
It's required to prevent echo from outputting a new line character after the string.
The result of concatenation is redirected to a file, don't try to put it into a variable.
Bash uses C-style strings for variable value representation.
In the current case, the string would be zero-terminated earlier than expected.
Here is the content of `blob.bin` in ASCII and hex formats:
```bash
$ hexdump -C blob.bin 
00000000  62 6c 6f 62 20 31 39 00  53 6f 6d 65 20 66 69 6c  |blob 19.Some fil|
00000010  65 20 63 6f 6e 74 65 6e  74 2e 0a                 |e content..|
0000001b
```
Each Git object is compressed by zlib.
I'm not aware of any zlib compressor as a standalone binary.
An example in the Git book uses zlib Ruby library.
Ruby is not a part of default Linux distro.
Luckily, Python has zlib and is available by default in a lot of distributions.
Let's create a one-liner compressor in Python:
```bash
compress() { python3 -c 'import sys,zlib; sys.stdout.buffer.write(zlib.compress(sys.stdin.buffer.read()))'; }
```

As you remember, Git is a key-value data storage.
So far, we were talking about values, the data inside git-objects.
The key is calculated as a SHA-1 hash for the value.
Git stores objects in the `.git/objects` folder.
The folder consists of other folders, which are the first two characters of the SHA-1, where the object files are located, named by the remaining 38 characters, e.g., `.git/objects/d6/70460b4b4aece5915caf5c68d12f560a9fe3e4`.
Let's put our blob in the appropriate place:
```bash
getSha() { shasum $1 | cut -d ' ' -f 1; }
BLOB_SHA=`getSha blob.bin`
mkdir -p .git/objects/"${BLOB_SHA:0:2}"
compress < blob.bin > .git/objects/"${BLOB_SHA:0:2}"/"${BLOB_SHA:2:38}"
```

The next step is the tree object.
The tree object describes a folder.
Here we assign a file name and permission with its content - blob object.
The blob object is addressed by its SHA.
We already have the hash calculated, but it's in hexadecimal format.
The tree object requires it in raw bytes, it can be converted like this:
```bash
RAW_BYTES_BLOB_SHA=`printf '%b' "$(echo "$BLOB_SHA" | sed 's/../\\\\x&/g')"`
```

Here are those two SHA sums printed by hexdump to show the difference:
```bash
$ echo -n "$BLOB_SHA" | hexdump -C
00000000  39 33 33 65 66 61 37 65  36 65 32 62 33 35 63 32  |933efa7e6e2b35c2|
00000010  37 62 36 35 66 30 65 38  37 38 34 65 66 37 38 34  |7b65f0e8784ef784|
00000020  38 30 34 64 33 36 61 63                           |804d36ac|
00000028
$ echo -n "$RAW_BYTES_BLOB_SHA" | hexdump -C
00000000  93 3e fa 7e 6e 2b 35 c2  7b 65 f0 e8 78 4e f7 84  |.>.~n+5.{e..xN..|
00000010  80 4d 36 ac                                       |.M6.|
00000014
```

Inside the tree object, a file described by template `<access> <fineName>\0<rawBytesSHA>`.
Let's put it into a separate file to calculate its size more easily.
```bash
{ echo -n '100644 file.txt'; zero; echo -n "$RAW_BYTES_BLOB_SHA"; } > tree.content
{ echo -n "tree $(size 'tree.content')"; zero; cat tree.content; } > tree.bin
```

So the `tree.bin` content would be:
```bash
$ hexdump -C tree.bin 
00000000  74 72 65 65 20 33 36 00  31 30 30 36 34 34 20 66  |tree 36.100644 f|
00000010  69 6c 65 2e 74 78 74 00  93 3e fa 7e 6e 2b 35 c2  |ile.txt..>.~n+5.|
00000020  7b 65 f0 e8 78 4e f7 84  80 4d 36 ac              |{e..xN...M6.|
0000002c
```

Compressing and moving to `.git/objects` the same way as for blob:
```bash
TREE_SHA=`getSha tree.bin`
mkdir .git/objects/"${TREE_SHA:0:2}"
compress < tree.bin > .git/objects/"${TREE_SHA:0:2}"/"${TREE_SHA:2:38}"
```

The last git-object we need is commit.
The commit refers to the tree-object by hexadecimal hash.
Each commit should have its author and commiter with a timestamp (1 second would be hardcoded here).
And, of course, the commit message.
```bash
echo "tree $TREE_SHA
author Anton <Strannik.Anton@gmail.com> 1 +0000
committer Anton <Strannik.Anton@gmail.com> 1 +0000

Initial commit
" > commit.body
{ echo -n "commit $(size 'commit.body')"; zero; cat commit.body; } > commit.bin
COMMIT_SHA=`getSha commit.bin`
mkdir .git/objects/"${COMMIT_SHA:0:2}"
compress < commit.bin > .git/objects/"${COMMIT_SHA:0:2}"/"${COMMIT_SHA:2:38}"
```

Now, we have all the needed git-objects.
We can check out the commit by its SHA, but why not create a "manual" branch for it?
To do so, we have to put the sha into a text file named after the branch.
```bash
mkdir -p .git/refs/heads
echo $COMMIT_SHA > .git/refs/heads/manual
```

It seems that we are all set to check out our commit by the branch name.
Unfortunately, the `.git` folder in its current state wouldn't be recognizable by Git as a repo.
The Git expects to see the currently checked out head.
Let's pretend that we had a "master" branch here.
```bash
echo "ref: refs/heads/master" > .git/HEAD
```

Here it is.
We can use Git commands to check the repo integrity and checkout the branch:
```bash
$ git fsck
Checking ref database: 100% (1/1), done.
Checking object directories: 100% (256/256), done.
$ git checkout manual
Switched to branch 'manual'
$ cat file.txt
Some file content.
```

Full script in one piece:
```bash
#!/usr/bin/env bash
set -xeuo pipefail

compress() { python3 -c 'import sys,zlib; sys.stdout.buffer.write(zlib.compress(sys.stdin.buffer.read()))'; }
getSha() { shasum $1 | cut -d ' ' -f 1; }
size() { wc -c < $1; }
zero() { printf '\0'; }

# Creating blob
echo "Some file content." > file.content
{ echo -n "blob $(size 'file.content')"; zero; cat file.content; } > blob.bin
BLOB_SHA=`getSha blob.bin`
mkdir -p .git/objects/"${BLOB_SHA:0:2}"
compress < blob.bin > .git/objects/"${BLOB_SHA:0:2}"/"${BLOB_SHA:2:38}"

# Creating tree
RAW_BYTES_BLOB_SHA=`printf '%b' "$(echo "$BLOB_SHA" | sed 's/../\\\\x&/g')"`
{ echo -n '100644 file.txt'; zero; echo -n "$RAW_BYTES_BLOB_SHA"; } > tree.content
{ echo -n "tree $(size 'tree.content')"; zero; cat tree.content; } > tree.bin
TREE_SHA=`getSha tree.bin`
mkdir .git/objects/"${TREE_SHA:0:2}"
compress < tree.bin > .git/objects/"${TREE_SHA:0:2}"/"${TREE_SHA:2:38}"

# Creating commit
echo "tree $TREE_SHA
author Anton <Strannik.Anton@gmail.com> 1 +0000
committer Anton <Strannik.Anton@gmail.com> 1 +0000

Initial commit
" > commit.body
{ echo -n "commit $(size 'commit.body')"; zero; cat commit.body; } > commit.bin
COMMIT_SHA=`getSha commit.bin`
mkdir .git/objects/"${COMMIT_SHA:0:2}"
compress < commit.bin > .git/objects/"${COMMIT_SHA:0:2}"/"${COMMIT_SHA:2:38}"

# A branch creation
mkdir -p .git/refs/heads
echo $COMMIT_SHA > .git/refs/heads/manual

# Add HEAD info
echo "ref: refs/heads/master" > .git/HEAD

# Check objects
git fsck

# Check the result by checkouting the branch
git checkout manual

# Read the file
cat file.txt
```
