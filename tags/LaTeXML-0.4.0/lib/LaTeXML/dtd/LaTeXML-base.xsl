<?xml version="1.0" encoding="utf-8"?>
<!--
 /=====================================================================\ 
 |  LaTeXML-base.xsl                                                   |
 | Base Stylesheet for converting LaTeXML documents to html or xhtml   |
 | included by LaTeXML-html.xsl and LaTeXML-xhtml.xsl                  |
 |=====================================================================|
 | Part of LaTeXML:                                                    |
 |  Public domain software, produced as part of work done by the       |
 |  United States Government & not subject to copyright in the US.     |
 |=====================================================================|
 | Bruce Miller <bruce.miller@nist.gov>                        #_#     |
 | http://dlmf.nist.gov/LaTeXML/                              (o o)    |
 \=========================================================ooo==U==ooo=/
-->
<xsl:stylesheet 
   xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
   version="1.0"
   xmlns:ltx="http://dlmf.nist.gov/LaTeXML"
   exclude-result-prefixes='ltx'
   >
<xsl:param name="CSS"></xsl:param>

<!--  ======================================================================
      The Page
      ====================================================================== -->

<xsl:template match="/">
  <html>
    <head>
      <title><xsl:value-of select="normalize-space(*/ltx:title)"/></title>
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
      <style type="text/css">
	img.math { vertical-align:middle }
	.framed  { border:1px solid black;}
      </style>
      <xsl:if test='$CSS'>
	<link rel='stylesheet' type="text/css" href="{$CSS}"/> 
     </xsl:if>
    </head>
    <body>
      <xsl:call-template name="header"/>
      <xsl:apply-templates/>
      <xsl:call-template name="footer"/> 
    </body>
  </html>
</xsl:template>

<xsl:template match="metakeywords">
  <meta name="keywords" lang="en-us" content="{@keywords}"/>
</xsl:template>

<!--  ======================================================================
      Header & Footer
      ====================================================================== -->
<xsl:template name="header">
  <div class='header'>
    <xsl:if test="//ltx:title">
      <xsl:apply-templates mode="TOC"/>
    </xsl:if>
  </div>
</xsl:template>

<xsl:template name="footer">
  <div class='footer'>
    <xsl:value-of select='//ltx:creationdate/node()'/>
  </div>
</xsl:template>

<!-- ======================================================================
     Document Structure
     ====================================================================== -->

<xsl:template match="ltx:document | ltx:chapter | ltx:part 
		     | ltx:section | ltx:subsection | ltx:subsubsection
		     | ltx:paragraph | ltx:sidebar | ltx:bibliography | ltx:appendix">
  <div class="{local-name()}">
    <xsl:call-template name="add_id"/>
    <xsl:apply-templates/>
  </div>
</xsl:template>

<xsl:template match="ltx:author">
  <div class='author'>
    <xsl:apply-templates/>
  </div>
</xsl:template>

<xsl:template match="ltx:affiliation">
  <div class='affiliation'><xsl:apply-templates/></div>
</xsl:template>

<!-- put in footer -->
<xsl:template match="ltx:creationdate"/>

<!--  ======================================================================
      Titles.
      ====================================================================== -->
<!-- Hack to determine the `levels' of various sectioning.
     Given that the nesting could consist of any of
     document/part/chapter/section or appendix/subsection/subsubsection
       /paragraph/subparagraph
     We'd like to assign h1,h2,... sensibly.
     Or should the DTD be more specific? -->
<xsl:param name="document_level">
  <xsl:value-of select="number(boolean(ltx:document))"/>
</xsl:param>

<xsl:param name="part_level">
  <xsl:value-of select="$document_level+number(boolean(//ltx:part))"/>
</xsl:param>

<xsl:param name="chapter_level">
  <xsl:value-of select="$part_level+number(boolean(//ltx:chapter))"/>
</xsl:param>

<xsl:param name="section_level">
  <xsl:value-of select="$chapter_level+number(boolean(//ltx:section))"/>
</xsl:param>

<xsl:param name="appendix_level">
  <xsl:value-of select="$chapter_level+number(boolean(//ltx:appendix))"/>
</xsl:param>

<xsl:param name="subsection_level">
  <xsl:value-of select="$section_level+number(boolean(//ltx:subsection))"/>
</xsl:param>

<xsl:param name="subsubsection_level">
  <xsl:value-of select="$subsection_level+number(boolean(//ltx:subsubsection))"/>
</xsl:param>

<xsl:param name="paragraph_level">
  <xsl:value-of select="$subsubsection_level+number(boolean(//ltx:paragraph))"/>
</xsl:param>

<xsl:param name="subparagraph_level">
  <xsl:value-of select="$paragraph_level+number(boolean(//ltx:subparagraph))"/>
</xsl:param>

<!-- and hope we haven't past 6!!! -->

<xsl:template match="ltx:document/ltx:title">
  <xsl:element name="{concat('h',$document_level)}">
    <xsl:call-template name="maketitle"/>
  </xsl:element>
</xsl:template>

<xsl:template match="ltx:part/ltx:title">
  <xsl:element name="{concat('h',$part_level)}">
    <xsl:call-template name="maketitle"/>
  </xsl:element>
</xsl:template>

<xsl:template match="ltx:chapter/ltx:title">
  <xsl:element name="{concat('h',$chapter_level)}">
    <xsl:call-template name="maketitle"/>
  </xsl:element>
</xsl:template>
<xsl:template match="ltx:section/ltx:title">
  <xsl:element name="{concat('h',$section_level)}">
    <xsl:call-template name="maketitle"/>
  </xsl:element>
</xsl:template>
<xsl:template match="ltx:appendix/ltx:title">
  <xsl:element name="{concat('h',$appendix_level)}">
    Appendix <xsl:call-template name="maketitle"/></xsl:element>
</xsl:template>
<xsl:template match="ltx:subsection/ltx:title">
  <xsl:element name="{concat('h',$subsection_level)}">
    <xsl:call-template name="maketitle"/>
  </xsl:element>
</xsl:template>
<xsl:template match="ltx:subsubsection/ltx:title">
  <xsl:element name="{concat('h',$subsubsection_level)}">
    <xsl:call-template name="maketitle"/>
  </xsl:element>
</xsl:template>
<xsl:template match="ltx:paragraph/ltx:title">
  <xsl:element name="{concat('h',$paragraph_level)}">
    <xsl:call-template name="maketitle"/>
  </xsl:element>
</xsl:template>
<xsl:template match="ltx:subparagraph/ltx:title">
  <xsl:element name="{concat('h',$subparagraph_level)}">
    <xsl:call-template name="maketitle"/>
  </xsl:element>
</xsl:template>

<xsl:template match="ltx:title">
  <h6><xsl:call-template name="maketitle"/></h6>
</xsl:template>

<xsl:template name="maketitle">
  <xsl:if test="../@refnum and not(../@refnum = '')">
    <xsl:value-of select="../@refnum"/>.<xsl:text> </xsl:text>
  </xsl:if>
  <xsl:apply-templates mode="intitle"/>
</xsl:template>

<xsl:template match="ltx:toctitle"/>

<!--  ======================================================================
      Tables of Contents.
      ====================================================================== -->
<xsl:param name="TOC_MAX_DEPTH">2</xsl:param>
<xsl:template match="*" mode="TOC"/>

<xsl:template match="ltx:document|ltx:part|ltx:chapter
		     |ltx:section|ltx:appendix|ltx:subsection|ltx:subsubsection
                     |ltx:paragraph|ltx:subparagraph" mode="TOC">
  <xsl:param name="TOC_DEPTH">0</xsl:param>
  <xsl:choose>
    <xsl:when test="$TOC_DEPTH &gt; $TOC_MAX_DEPTH"/>
    <xsl:when test="$TOC_DEPTH &gt; 0">
      <li><xsl:call-template name="inTOC">
	  <xsl:with-param name="TOC_DEPTH" select="$TOC_DEPTH"/>
	  </xsl:call-template>
      </li>
    </xsl:when>
    <xsl:otherwise>
      <xsl:call-template name="inTOC">
	<xsl:with-param name="TOC_DEPTH" select="$TOC_DEPTH"/>
      </xsl:call-template>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template name="inTOC">
  <xsl:param name="TOC_DEPTH">0</xsl:param>
  <xsl:apply-templates select="ltx:title" mode="toctitle"/>
  <xsl:if test="ltx:part|ltx:chapter|ltx:section|ltx:appendix|ltx:subsection
                |ltx:subsubsection|ltx:paragraph|ltx:subparagraph">
    <ul><xsl:apply-templates mode="TOC">
	<xsl:with-param name="TOC_DEPTH" select="1+$TOC_DEPTH"/>
      </xsl:apply-templates>
    </ul>
  </xsl:if>
</xsl:template>

<xsl:template match="ltx:title" mode="toctitle">
  <xsl:element name="a">
    <xsl:attribute name="href">
      <xsl:choose>
	<xsl:when test="../@label"><xsl:value-of select="concat('#',../@label)"/></xsl:when>
	<xsl:otherwise><xsl:value-of select="concat('#',generate-id(..))"/></xsl:otherwise>
      </xsl:choose>
    </xsl:attribute>
    <xsl:if test="../@refnum">
      <xsl:value-of select="../@refnum"/>.<xsl:text> </xsl:text>
    </xsl:if>
    <xsl:apply-templates mode="toctitle"/>
  </xsl:element>
</xsl:template>

<!--  ======================================================================
      Refnums and such
      ====================================================================== -->

<xsl:template match="ltx:ref[text()] | ltx:qref[text()]">
  <a href="{concat('#',@labelref)}" class="refnum"><xsl:apply-templates/></a>
</xsl:template>

<xsl:template match="ltx:ref | ltx:qref">
  <a href="{concat('#',@labelref)}" class="refnum"><xsl:value-of select="@labelref"/></a>
</xsl:template>

<xsl:template match="ltx:eqref">(<a href="{concat('#',@labelref)}" class="refnum"><xsl:value-of select="@labelref"/></a>)</xsl:template>

<!-- ======================================================================
     Math level
     Really MathML !!!
     ====================================================================== -->
<xsl:template match="ltx:equation">
  <div class='equation'> 
    <xsl:call-template name="add_id"/>
    <xsl:apply-templates select="@refnum"/>
    <span class='equationcontent'>
      <xsl:apply-templates select="ltx:Math"/>
    </span>
  </div>
</xsl:template>


<!-- ignore (if preceded by an XMath?) -->
<xsl:template match="ltx:punct"/>

<!-- ======================================================================
     Block Elements
     ====================================================================== -->

<xsl:template match="ltx:p">
  <p><xsl:apply-templates/></p>
</xsl:template>

<xsl:template match="ltx:toccaption"/>
<xsl:template match="ltx:caption">
  <div class='caption'>  
    <xsl:apply-templates select="../@refnum"/>
    <xsl:apply-templates/>
  </div>
</xsl:template>

<xsl:template match="ltx:figure | ltx:table">
  <div class='{local-name()}'>
  <xsl:call-template name="add_id"/>
    <xsl:apply-templates/>
  </div>
</xsl:template>

<xsl:template match="ltx:tabular">
  <table align='center' frame='{@frame}' rules='{@rules}'>
    <xsl:apply-templates/>
  </table>
</xsl:template>

<xsl:template match="ltx:colgroup">
  <colgroup><xsl:call-template name="col-attributes"/><xsl:apply-templates/></colgroup>
</xsl:template>

<xsl:template match="ltx:col">
  <col><xsl:call-template name="col-attributes"/><xsl:apply-templates/></col>
</xsl:template>

<xsl:template name="col-attributes">
  <xsl:if test="@span">
    <xsl:attribute name='span'><xsl:value-of select='@span'/></xsl:attribute>
  </xsl:if>
  <xsl:if test="@align">
    <xsl:attribute name='align'><xsl:value-of select='@align'/></xsl:attribute>
  </xsl:if>
</xsl:template>

<xsl:template match="ltx:thead">
  <thead><xsl:apply-templates/></thead>
</xsl:template>

<xsl:template match="ltx:tbody">
  <tbody><xsl:apply-templates/></tbody>
</xsl:template>

<xsl:template match="ltx:tfoot">
  <tfoot><xsl:apply-templates/></tfoot>
</xsl:template>

<xsl:template match="ltx:tr">
  <tr><xsl:apply-templates/></tr>
</xsl:template>

<xsl:template match="ltx:td">
  <td><xsl:call-template name="cell-attributes"/><xsl:apply-templates/></td>
</xsl:template>

<xsl:template match="ltx:th">
  <th><xsl:call-template name="cell-attributes"/><xsl:apply-templates/></th>
</xsl:template>

<xsl:template name="cell-attributes">
  <xsl:if test="@rowspan">
    <xsl:attribute name='rowspan'><xsl:value-of select='@rowspan'/></xsl:attribute>
  </xsl:if>
  <xsl:if test="@colspan">
    <xsl:attribute name='colspan'><xsl:value-of select='@colspan'/></xsl:attribute>
  </xsl:if>
  <xsl:if test="@align">
    <xsl:attribute name='align'><xsl:value-of select='@align'/></xsl:attribute>
  </xsl:if>
</xsl:template>

<xsl:template match="ltx:graphics">
  <img src="{@src}" width="{@width}" height="{@height}"/>
</xsl:template>

<xsl:template match="ltx:quote">
  <blockquote>
    <xsl:apply-templates/>
  </blockquote>
</xsl:template>

<xsl:template match="ltx:ERROR">
  <span class="ERROR" style="color:red"><xsl:apply-templates/></span>
</xsl:template>
<!-- ======================================================================
     Lists
     ====================================================================== -->

<xsl:template name="copy-class">
  <xsl:if test="@class">
    <xsl:attribute name="class">
      <xsl:value-of select="@class"/>
    </xsl:attribute>
  </xsl:if>
</xsl:template>

<xsl:template match="ltx:itemize">
  <ul>
    <xsl:call-template name="copy-class"/>
    <xsl:apply-templates/>
  </ul>
</xsl:template>

<xsl:template match="ltx:enumerate">
  <ol>
    <xsl:call-template name="copy-class"/>
    <xsl:apply-templates/>
  </ol>
</xsl:template>

<xsl:template match="ltx:item">
  <li><xsl:apply-templates/></li>
</xsl:template>

<xsl:template match="ltx:description">
  <dl class="description">
    <xsl:call-template name="copy-class"/>
    <xsl:apply-templates mode='description'/>
  </dl>
</xsl:template>

<xsl:template match="ltx:item" mode="description">
  <dt><xsl:value-of select="@tag"/><xsl:apply-templates select="ltx:tag/node()"/></dt>
  <dd><xsl:apply-templates/></dd>
</xsl:template>

<xsl:template match="ltx:tag"/>
<!-- ======================================================================
     Inline Elements
     ====================================================================== -->

<xsl:template match="ltx:a">
  <a href="{@href}"><xsl:apply-templates/></a>
</xsl:template>


<xsl:template match="ltx:text">
  <xsl:choose>
    <xsl:when test="@font='typewriter'"><tt  ><xsl:apply-templates select='.' mode='faced'/></tt  ></xsl:when>
    <xsl:when test="@font='bold'"      ><b   ><xsl:apply-templates select='.' mode='faced'/></b   ></xsl:when>
    <xsl:when test="@font='italic'"    ><i   ><xsl:apply-templates select='.' mode='faced'/></i   ></xsl:when>
    <xsl:otherwise                     ><span><xsl:apply-templates select='.' mode='faced'/></span></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template match="ltx:text" mode='faced'>
  <xsl:if test="@framed">
    <xsl:attribute name='class'>framed</xsl:attribute>
  </xsl:if>
  <xsl:if test="@raise">
    <xsl:attribute name='style'>position:relative; bottom:<xsl:value-of select="@raise"/></xsl:attribute>
  </xsl:if>
  <xsl:apply-templates/>
</xsl:template>

<xsl:template match="ltx:emph">
  <em><xsl:apply-templates/></em>
</xsl:template>

<xsl:template match="ltx:cite[@style='intext']">
  <xsl:apply-templates select="citepre"/>
  <!--  <xsl:apply-templates select="bibref"/>-->
  <xsl:value-of select="@ref"/>
  <xsl:apply-templates select="citepost"/>
</xsl:template>

<xsl:template match="ltx:cite">
  (<xsl:apply-templates select="citepre"/>
<!-- <xsl:apply-templates select="bibref"/>-->
   <xsl:value-of select="@ref"/>
   <xsl:apply-templates select="citepost"/>)</xsl:template>

<xsl:template match="ltx:bibref">
  <a href="{@href}"><xsl:apply-templates/></a>
</xsl:template>

<xsl:template match="ltx:citepre[../@style='intext'] | citepost[../@style='intext']"
  >(<xsl:apply-templates/>)</xsl:template>

<xsl:template match="ltx:citepre"><xsl:apply-templates/><xsl:text> </xsl:text></xsl:template>

<xsl:template match="ltx:citepost">; <xsl:apply-templates/></xsl:template>

<!-- ======================================================================
     The Index
     ====================================================================== -->
<xsl:template match="ltx:index"/>

<xsl:template match="ltx:indexentry">
  <li id="{@label}">
   <span class='indexline'>
    <xsl:apply-templates select="indexlevel"/>
    <xsl:apply-templates select="indexrefs"/>
  </span>
  <xsl:apply-templates select="indexlist"/>
  </li>
</xsl:template>

<xsl:template match="ltx:indexlevel[../@label]">
  <a name="{../@label}" class="indexlevel">
    <xsl:apply-templates/>
  </a>
</xsl:template>

<xsl:template match="ltx:indexlevel">
  <span class="indexlevel">
    <xsl:apply-templates/>
  </span>
</xsl:template>

<xsl:template match="ltx:indexrefs">
  <xsl:text> </xsl:text>
  <xsl:apply-templates/>
</xsl:template>

<xsl:template match="ltx:indexlist">
  <ul class="indexlist">
    <xsl:apply-templates/>
  </ul>
</xsl:template>

<!-- ======================================================================
     Bibliography
     ====================================================================== -->
<xsl:template match="ltx:biblist">
  <ul class="biblist">
    <xsl:apply-templates/>
  </ul>
</xsl:template>

<xsl:template match="ltx:bibitem">
  <li id="{@label}" class="bibitem">
    <a name="{@label}" class="bib-ay"><xsl:apply-templates select="fbib-author-year"/></a>
    <xsl:apply-templates select="fbib-title | fbib-data | fbib-extra"/>
  </li>
</xsl:template>

<xsl:template match="ltx:fbib-title | ltx:fbib-data | ltx:fbib-extra">
  <br/><xsl:apply-templates/>
</xsl:template>

<xsl:template match="ltx:bib-mr">
  <a href="{concat('http://www.ams.org/mathscinet-getitem?mr=',text())}"><xsl:apply-templates/>(MathRev)</a>
</xsl:template>

<xsl:template match="ltx:bib-doi">
  <a href="{concat('http://dx.doi.org/',text())}"><xsl:apply-templates/></a>
</xsl:template>

<xsl:template match="ltx:bib-url">
  <a href="{concat('http://dx.doi.org/',text())}"><xsl:apply-templates/></a>
</xsl:template>

<!-- ======================================================================
     Meta data
     ====================================================================== -->

<xsl:template match="ltx:email">
  <a href="{concat('mailto:',text())}"><xsl:value-of select="text()"/></a>
</xsl:template>

<xsl:template match="ltx:metadata">
  <dl class="metadata">
    <xsl:apply-templates/>
  </dl>
</xsl:template>

<xsl:template match="ltx:sources">
  <dt>Sources</dt>
  <dd><ul><xsl:apply-templates/></ul></dd>
</xsl:template>

<xsl:template match="ltx:source">
  <li class="source"><xsl:apply-templates select="node()"/></li>
</xsl:template>

<xsl:template match="ltx:notes">
  <dt>Notes</dt>
  <dd><ul><xsl:apply-templates/></ul></dd>
</xsl:template>

<xsl:template match="ltx:note">
  <li class="note"><xsl:apply-templates select="node()"/></li>
</xsl:template>

<xsl:template match="ltx:keywords">
  <dt>Keywords</dt>
  <dd class="keywords"><ul><li><xsl:apply-templates/></li></ul></dd>
</xsl:template>

<xsl:template match="ltx:keyword">
  <a href="{@href}" class="keyword"><xsl:apply-templates/></a>
</xsl:template>

<xsl:template match="ltx:index"/>

<xsl:template match="referrers">
  <dt>Ref'd&#160;by</dt>
  <dd class="referrers"><ul><li><xsl:apply-templates/></li></ul></dd>
</xsl:template>

<xsl:template match="referrer">
  <a href="{@href}" class='referrer'><xsl:apply-templates/></a>
</xsl:template>

<xsl:template match="ltx:acknowledgements">
  <dt>Acknowledgments</dt>
  <dd class='acknowledgements'><xsl:apply-templates select="node()"/></dd>
</xsl:template>

</xsl:stylesheet>
