**LaTeXML GIT Repository**

This repository houses the LaTeXML software used to maintain vismor.com.

There are two active branches:

- NIST: mirrors the LaTeXML svn repository at nist.gov.
- master: NIST merged with customizations used for maintaining vismor.com.

Note to self. To update the NIST branch:

1. git checkout NIST     // Switch local HEAD to NIST
2. git svn rebase        // Update local NIST from svn
3. git push origin NIST  // Push update to NIST branch on GitHub
3. git checkout master   // Switch local HEAD back to master


**LaTeXML Functionality**

At vismor.com documents are maintained in Scrivener as MultiMarkdown. When updates to the site are
required, the MultiMarkdown documents are compiled into TeX files by Scrivener. The TeX files are 
then converted to PDF documents and XHTML web documents. LaTexML is used for the TeX &mdash;&gt; XHTML 
conversion. It is particularly adept at TeX &mdash;&gt; MathML conversions. It is also quite good at
converting large TeX documents into an interlinked set of XTHML pages including navigation, table of
contents, and bibliography.

To quote from its description at the [LaTexML web site](http://dlmf.nist.gov/LaTeXML):

> In brief, latexml is a program, written in Perl, that attempts to faithfully mimic TeX’s behaviour, 
> but produces XML instead of dvi. The document model of the target XML makes explicit the model implied 
> by LaTeX. The processing and model are both extensible; you can define the mapping between TeX constructs 
> and the XML fragments to be created. A postprocessor, latexmlpost converts this XML into other formats 
> such as HTML or XHTML, with options to convert the math into MathML (currently only presentation) or 
> images.

Visit the site for more information.